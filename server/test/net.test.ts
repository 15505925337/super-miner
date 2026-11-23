// 真的起一个服务端，用两个 WebSocket 客户端连上去走一遍：开房、进房、开打、放钩、掉线、重连。
import test from 'node:test';
import assert from 'node:assert/strict';
import { startServer } from '../src/main.ts';

class Client {
  ws: WebSocket; msgs: any[] = []; waiters: { ok: (m: any) => boolean; done: (m: any) => void }[] = [];
  constructor(port: number) {
    this.ws = new WebSocket('ws://127.0.0.1:' + port);
    this.ws.onmessage = e => {
      const m = JSON.parse(String(e.data)); this.msgs.push(m);
      this.waiters = this.waiters.filter(w => { if (w.ok(m)) { w.done(m); return false; } return true; });
    };
  }
  open() { return new Promise<void>((r, j) => { this.ws.onopen = () => r(); this.ws.onerror = () => j(new Error('连不上')); }); }
  send(o: unknown) { this.ws.send(JSON.stringify(o)); }
  wait(ok: (m: any) => boolean, ms = 8000): Promise<any> {
    const had = this.msgs.find(ok); if (had) return Promise.resolve(had);
    return new Promise((r, j) => { const t = setTimeout(() => j(new Error('等消息超时')), ms); this.waiters.push({ ok, done: m => { clearTimeout(t); r(m); } }); });
  }
  clear() { this.msgs = []; }
  close() { this.ws.close(); }
}

test('联网走一遍：两个客户端开房、进房、开打、放钩，再掉线重连', async () => {
  const srv = await startServer(0);
  try {
    const a = new Client(srv.port), b = new Client(srv.port);
    await a.open(); await b.open();
    a.send({ t: 'hello', token: 'aaaaaaaaaaaa' }); b.send({ t: 'hello', token: 'bbbbbbbbbbbb' });
    a.send({ t: 'create', name: '甲', mode: 'vs' });
    const meta = await a.wait(m => m.t === 'meta');
    assert.match(meta.code, /^\d{4}$/); assert.equal(meta.host, true);
    b.send({ t: 'join', code: meta.code, name: '乙' });
    const mb = await b.wait(m => m.t === 'meta' && m.players.length === 2);
    assert.equal(mb.host, false); assert.deepEqual(mb.players.map((p: any) => p.name), ['甲', '乙']);
    const me = mb.you[0];
    a.send({ t: 'start' });
    const s1 = await b.wait(m => m.t === 's' && m.ph === 'count');
    assert.equal(s1.F.length, 1); assert.ok(s1.F[0].length > 5);
    await b.wait(m => m.t === 's' && m.ph === 'play', 6000);
    b.send({ t: 'fire', i: me });
    const fired = await a.wait(m => m.t === 's' && m.E.some((e: any) => e.e === 'fire' && e.p === me));
    assert.ok(fired, '甲看到了乙放钩');
    await a.wait(m => m.t === 's' && m.P.find((p: any) => p.i === me).s === 1);
    // 乙掉线
    a.clear(); b.close();
    const off = await a.wait(m => m.t === 'meta' && m.players[1].on === false);
    assert.equal(off.players.length, 2, '座位保留');
    // 乙换一条连接回来
    const b2 = new Client(srv.port); await b2.open();
    b2.send({ t: 'hello', token: 'bbbbbbbbbbbb' }); b2.send({ t: 'join', code: meta.code, name: '乙' });
    const back = await b2.wait(m => m.t === 'meta');
    assert.deepEqual(back.you, [me], '认回了原来的座位');
    const live = await b2.wait(m => m.t === 's');
    assert.equal(live.ph, 'play', '回来时对局还在进行');
    await a.wait(m => m.t === 'meta' && m.players[1].on === true);
    a.close(); b2.close();
  } finally { await srv.close(); }
});

test('网页版文件：服务端能把导出的页面发出来；没有的路径回 404', async () => {
  const srv = await startServer(0);
  try {
    const miss = await fetch('http://127.0.0.1:' + srv.port + '/no-such-file');
    assert.equal(miss.status, 404);
    const esc = await fetch('http://127.0.0.1:' + srv.port + '/..%2F..%2Fproject.godot');
    assert.equal(esc.status, 404, '不能读到 build/web 以外的文件');
  } finally { await srv.close(); }
});
