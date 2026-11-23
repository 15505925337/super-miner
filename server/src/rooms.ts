// 房间管理和消息处理：开房、进房、掉线重连、房主操作、把玩家的按键转给规则。
import { MAXP, MODES, BOT_NAMES, RULES, SHOP } from './core.ts';
import type { Room, Player, Conn, Mode } from './core.ts';
import { newRoom, newPlayer, layout, startGame, toLobby, fire, useTool, setSoloPaused, tickRoom, snapshot } from './game.ts';
import { buyClick, keeperAct } from './shop.ts';
import { emote, matchLog, EVENT_KEYS } from './fun.ts';
import { mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

export class Hub {
  rooms = new Map<string, Room>();
  rnd: () => number;
  urls: () => string[];
  logDir: string | null;            // 对局记录存哪个目录；不给就不存（测试里用）
  logs: Record<string, unknown>[] = [];   // 最近几场的记录（测试和排查用）
  constructor(rnd: () => number = Math.random, urls: () => string[] = () => [], logDir: string | null = null) { this.rnd = rnd; this.urls = urls; this.logDir = logDir; }

  mkRoom(): Room {
    let code: string;
    do { code = String(1000 + Math.floor(this.rnd() * 9000)); } while (this.rooms.has(code));
    const room = newRoom(code, this.rnd);
    // 调试用：环境变量 DM_EVENTS=rain,cave,dark 指定每一关的随机事件。正式运行不要设
    if (process.env.DM_EVENTS) room.forceEvents = process.env.DM_EVENTS.split(',').map((s: string) => EVENT_KEYS.includes(s.trim()) ? s.trim() : '');
    this.rooms.set(code, room);
    return room;
  }
  cleanName(name: unknown, room: Room): string {
    const s = String(name == null ? '' : name).replace(/\s+/g, ' ').trim().slice(0, 10);
    return s || '矿工' + (room.players.length + 1);
  }
  // 房间名单（谁在、谁是房主、哪些座位是你的）。每条连接看到的"你"不一样，所以逐个发
  sendMeta(room: Room): void {
    const players = room.players.map(p => ({ id: p.id, name: p.name, c: p.c, bot: p.bot, on: !!(p.bot || p.conn), x: p.x }));
    const hostPlayer = room.players.find(p => !p.bot && p.token === room.host);
    for (const conn of room.conns) {
      conn.send({
        t: 'meta', code: room.code, mode: room.mode, rounds: room.rounds, urls: this.urls(), players,
        host: room.host === conn.token, hostId: hostPlayer ? hostPlayer.id : 0, you: room.players.filter(p => p.conn === conn).map(p => p.id),
      });
    }
  }
  joinRoom(conn: Conn, room: Room, name: unknown): void {
    const mine = room.players.filter(p => !p.bot && p.token === conn.token);
    if (mine.length) {                                       // 掉线重连：按 token 认回原来的座位
      for (const p of mine) {
        if (p.conn && p.conn !== conn) { const old = p.conn; room.conns.delete(old); old.room = null; old.close(); }
        p.conn = conn;
      }
    } else {
      if (room.ph !== 'lobby') { conn.send({ t: 'err', gone: 1, msg: '这个房间已经开打了，等他们打完再进' }); return; }
      if (room.players.length >= MAXP) { conn.send({ t: 'err', gone: 1, msg: '房间满了，最多 4 人' }); return; }
      newPlayer(room, conn, this.cleanName(name, room));
    }
    conn.room = room; room.conns.add(conn); room.emptyAt = 0;
    if (![...room.conns].some(c => c.token === room.host)) room.host = conn.token;
    this.sendMeta(room); room.dirty = true;
  }
  leave(conn: Conn, nowMs: number = Date.now()): void {
    const room = conn.room; if (!room) return;
    conn.room = null; room.conns.delete(conn);
    if (room.ph === 'lobby') { room.players = room.players.filter(p => p.conn !== conn); layout(room); }
    else for (const p of room.players) if (p.conn === conn) p.conn = null;   // 对局中只标记掉线，座位留着
    setSoloPaused(room, true);
    if (!room.conns.size) { if (room.ph === 'lobby') this.rooms.delete(room.code); else room.emptyAt = nowMs; return; }
    if (room.host === conn.token) room.host = [...room.conns][0].token;
    this.sendMeta(room); room.dirty = true;
  }

  // 网页离开时会主动报一声（见导出配置里的 pagehide）：把这个身份的连接都当作断开。
  // 浏览器有时会把离开的页面整个冻起来留着，连接不断，不这样做别人会一直看到他"在线"
  dropToken(token: string, nowMs: number = Date.now()): number {
    let n = 0;
    for (const room of [...this.rooms.values()]) for (const c of [...room.conns]) {
      if (c.token !== token) continue;
      this.leave(c, nowMs); c.close(); n++;
    }
    return n;
  }

  onMsg(conn: Conn, m: any): void {
    if (!m || typeof m.t !== 'string') return;
    const room = conn.room;
    if (m.t === 'hello') { if (typeof m.token === 'string' && m.token.length >= 8) conn.token = m.token.slice(0, 40); return; }
    if (m.t === 'create') {
      if (room) return;
      if (this.rooms.size >= RULES.maxRooms) { conn.send({ t: 'err', msg: '房间太多了，稍后再试' }); return; }
      const r = this.mkRoom(); r.host = conn.token; if (MODES.includes(m.mode)) r.mode = m.mode as Mode;
      this.joinRoom(conn, r, m.name);
      if (r.mode === 'solo') { startGame(r); this.broadcast(r); }
      return;
    }
    if (m.t === 'join') {
      if (room) return;
      const r = this.rooms.get(String(m.code == null ? '' : m.code).trim());
      if (!r) { conn.send({ t: 'err', gone: 1, msg: '没有这个房间' }); return; }
      if (r.mode === 'solo') {
        if (!r.players.some(p => p.token === conn.token)) {
          conn.send({ t: 'err', gone: 1, msg: '这是单人闯关房间，不能加入' }); return;
        }
        setSoloPaused(r, true);
      }
      this.joinRoom(conn, r, m.name);
      if (r.mode === 'solo') this.broadcast(r);
      return;
    }
    if (!room) return;
    const isHost = room.host === conn.token;
    const own = (id: unknown): Player | undefined => room.players.find(p => p.id === id && p.conn === conn);
    switch (m.t) {
      case 'leave':
        this.leave(conn);
        if (room.mode === 'solo') this.rooms.delete(room.code);
        conn.send({ t: 'left' }); break;
      case 'cfg':
        if (!isHost || room.ph !== 'lobby') break;
        if (m.mode !== 'solo' && MODES.includes(m.mode)) room.mode = m.mode as Mode;
        if (m.rounds === 3 || m.rounds === 5) room.rounds = m.rounds;
        this.sendMeta(room); break;
      case 'addBot': {
        if (!isHost || room.ph !== 'lobby' || room.players.length >= MAXP) break;
        const name = BOT_NAMES.find(n => !room.players.some(p => p.name === n)) || '电脑';
        newPlayer(room, null, name, true); this.sendMeta(room); break;
      }
      case 'addLocal':                                       // 同一台设备上再加一个人，共用这条连接
        if (room.ph !== 'lobby' || room.players.length >= MAXP) break;
        newPlayer(room, conn, '玩家' + (room.players.length + 1)); this.sendMeta(room); break;
      case 'kick': {
        if (room.ph !== 'lobby') break;
        const p = room.players.find(q => q.id === m.id); if (!p) break;
        const mine = room.players.filter(q => q.conn === conn);
        const selfExtra = p.conn === conn && mine[0] !== p;  // 自己加的本机玩家可以自己撤掉
        if (!selfExtra && !(isHost && p.conn !== conn)) break;
        room.players = room.players.filter(q => q !== p); layout(room);
        const pc = p.conn;
        if (pc && pc !== conn && !room.players.some(q => q.conn === pc)) {
          room.conns.delete(pc); pc.room = null; pc.send({ t: 'left', msg: '你被房主请出了房间' });
        }
        this.sendMeta(room); break;
      }
      case 'start': if (isHost && room.ph === 'lobby' && room.players.length) startGame(room); break;
      case 'fire': { const p = own(m.i); if (p) fire(room, p, m.a); break; }
      case 'tool': { const p = own(m.i); if (p) useTool(room, p, String(m.k)); break; }
      case 'buy': { const p = own(m.i); if (p) buyClick(room, p, String(m.k)); break; }
      case 'haggle': { const p = own(m.i); if (p) keeperAct(room, p, 'offer', String(m.k), m.offer); break; }
      case 'say': {                                          // 跟老板说话；话里带数字又点着一件商品，就当出价
        const p = own(m.i); if (!p) break;
        const text = String(m.text == null ? '' : m.text).replace(/\s+/g, ' ').trim().slice(0, 60); if (!text) break;
        const num = text.match(/\d{2,5}/), k = typeof m.k === 'string' && Object.prototype.hasOwnProperty.call(SHOP, m.k) ? m.k : '';
        if (num && k) keeperAct(room, p, 'offer', k, Number(num[0]), text); else keeperAct(room, p, 'chat', k, null, text);
        break;
      }
      case 'pause':
        if (isHost && setSoloPaused(room, typeof m.paused === 'boolean' ? m.paused : !room.paused)) this.broadcast(room);
        break;
      case 'emote': { if (room.paused) break; const p = own(m.i); if (p) emote(room, p, m.k); break; }     // 快捷喊话：只收编号，不收文字
      case 'ready':
        if (room.ph !== 'shop') break;
        for (const p of room.players) if (p.conn === conn) p.ready = true;
        room.dirty = true; break;
      case 'again':
        if (!isHost || room.ph !== 'over') break;
        if (room.mode === 'solo') { startGame(room); this.broadcast(room); }
        else { toLobby(room); this.sendMeta(room); }
        break;
    }
  }

  // 所有房间往前走一步，并把状态发出去。对局中每帧都发，其余时候有变化才发
  tick(dt: number, nowMs: number = Date.now()): void {
    for (const room of this.rooms.values()) {
      if (!room.conns.size) { if (nowMs - room.emptyAt > RULES.emptyRoomSecs * 1000) this.rooms.delete(room.code); continue; }   // 人全掉线一阵子后清房
      try {
        tickRoom(room, dt);
        if (room.final && room.res && !room.logged) { room.logged = true; this.saveLog(room, nowMs); }   // 整场打完：存一份对局记录
        const live = !room.paused && (room.ph === 'count' || room.ph === 'play');
        if (live || room.dirty || room.acc % 6 === 0) { this.broadcast(room); room.dirty = false; }
      } catch (e) { console.error(e); }
    }
  }
  // 对局记录：每场一个文件。只有数字和用了什么，没有玩家打的字
  saveLog(room: Room, nowMs: number): void {
    const log = matchLog(room, nowMs);
    this.logs.push(log); if (this.logs.length > 20) this.logs.shift();
    if (!this.logDir) return;
    try {
      mkdirSync(this.logDir, { recursive: true });
      const stamp = new Date(nowMs).toISOString().replace(/[-:]/g, '').replace('T', '-').slice(0, 15);
      writeFileSync(join(this.logDir, `${stamp}-${room.code}-${room.mode}.json`), JSON.stringify(log, null, 2));
    } catch (e) { console.error('对局记录没存上', e); }
  }
  broadcast(room: Room): void {
    const o = snapshot(room);
    room.ev = [];
    for (const conn of room.conns) conn.send(o);
  }
}
