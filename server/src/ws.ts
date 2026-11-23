// 手写的 WebSocket 服务端（只用 Node 自带模块，不装第三方包）。
// 只支持本游戏用到的部分：文本帧、分片、ping/pong、关闭。单条消息最长 8192 字节。
import { createHash } from 'node:crypto';
import type { IncomingMessage } from 'node:http';
import type { Duplex } from 'node:stream';

export function wsFrame(op: number, payload: Buffer): Buffer {
  const n = payload.length; let h: Buffer;
  if (n < 126) h = Buffer.from([0x80 | op, n]);
  else if (n < 65536) { h = Buffer.alloc(4); h[0] = 0x80 | op; h[1] = 126; h.writeUInt16BE(n, 2); }
  else { h = Buffer.alloc(10); h[0] = 0x80 | op; h[1] = 127; h.writeUInt32BE(0, 2); h.writeUInt32BE(n, 6); }
  return Buffer.concat([h, payload]);
}

export interface Socket {
  send(o: unknown): void;            // 发一个 JSON 对象
  raw(frame: Buffer): void;          // 发一个已经编好的帧（同一份状态发给多人时省得重复编码）
  close(): void;
}

// 把一次 HTTP 升级请求接成 WebSocket。onJson 收到每条 JSON 消息时调，onClose 断开时调一次
export function acceptWs(req: IncomingMessage, sock: Duplex, onJson: (m: unknown) => void, onClose: () => void): Socket | null {
  const key = req.headers['sec-websocket-key'];
  if (!key || String(req.headers.upgrade).toLowerCase() !== 'websocket') { sock.destroy(); return null; }
  const accept = createHash('sha1').update(key + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11').digest('base64');
  sock.write('HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ' + accept + '\r\n\r\n');
  (sock as any).setNoDelay?.(true);
  const kill = () => { if (!sock.destroyed) sock.destroy(); };
  const out: Socket = {
    raw(frame) { if (!sock.destroyed && sock.writableLength < 1 << 20) sock.write(frame); },   // 对方太卡就丢帧
    send(o) { this.raw(wsFrame(1, Buffer.from(JSON.stringify(o)))); },
    close: kill,
  };
  let buf: Buffer = Buffer.alloc(0), frag: Buffer[] = [];
  sock.on('data', (chunk: Buffer) => {
    buf = buf.length ? Buffer.concat([buf, chunk]) : chunk;
    while (buf.length >= 2) {
      const fin = buf[0] & 0x80, op = buf[0] & 0x0f, masked = buf[1] & 0x80;
      let len = buf[1] & 0x7f, off = 2;
      if (len === 126) { if (buf.length < 4) return; len = buf.readUInt16BE(2); off = 4; }
      else if (len === 127) { kill(); return; }
      if (!masked || len > 8192) { kill(); return; }
      if (buf.length < off + 4 + len) return;
      const mask = buf.subarray(off, off + 4), data = Buffer.from(buf.subarray(off + 4, off + 4 + len));
      for (let i = 0; i < len; i++) data[i] ^= mask[i & 3];
      buf = buf.subarray(off + 4 + len);
      if (op === 8) { kill(); return; }
      if (op === 9) { out.raw(wsFrame(10, data)); continue; }
      if (op !== 0 && op !== 1) continue;
      frag.push(data);
      if (!fin) { if (frag.length > 8) { kill(); return; } continue; }
      const text = Buffer.concat(frag).toString('utf8'); frag = [];
      let m: unknown; try { m = JSON.parse(text); } catch { continue; }
      try { onJson(m); } catch (e) { console.error(e); }
    }
  });
  let closed = false;
  sock.on('close', () => { if (!closed) { closed = true; onClose(); } });
  sock.on('error', kill);
  return out;
}
