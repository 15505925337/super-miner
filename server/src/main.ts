// 服务端入口：一个进程同时做三件事
//   1. 游戏服务端：WebSocket + JSON，房间、对局、规则都在这里算（服务端权威）
//   2. 把 build/web 里导出的网页版发给浏览器（带 gzip 压缩）
//   3. 接收网页版自己发来的截图和帧率数据，存到 shots/（验收用）
// 启动：./server.sh   或   node server/src/main.ts [端口]
// 默认只允许本机访问。要让同一 WiFi 的其他设备进来：HOST=0.0.0.0 ./server.sh
import http from 'node:http';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import zlib from 'node:zlib';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { Hub } from './rooms.ts';
import { acceptWs } from './ws.ts';
import type { Conn } from './core.ts';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const WEB = path.join(ROOT, 'build', 'web'), SHOTS = path.join(ROOT, 'shots');
const MIME: Record<string, string> = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.wasm': 'application/wasm', '.pck': 'application/octet-stream', '.png': 'image/png', '.ico': 'image/x-icon', '.json': 'application/json' };

export function startServer(port: number, host: string = '127.0.0.1') {
  const lanUrls = () => {
    if (host === '127.0.0.1' || host === 'localhost') return [];
    const out: string[] = [];
    for (const list of Object.values(os.networkInterfaces()) as any[]) for (const i of list || []) if (i.family === 'IPv4' && !i.internal) out.push('http://' + i.address + ':' + port);
    return out;
  };
  const hub = new Hub(Math.random, lanUrls, path.join(ROOT, 'server', 'logs'));   // 对局记录存在 server/logs/
  const gz = new Map<string, Buffer>();

  const server = http.createServer((req: any, res: any) => {
    const u = new URL(req.url || '/', 'http://x');
    if (req.method === 'POST' && (u.pathname === '/__shot' || u.pathname === '/__stats')) {
      const name = (u.searchParams.get('name') || 'unnamed').replace(/[^\w.-]/g, '_');
      const chunks: Buffer[] = [];
      req.on('data', (c: Buffer) => chunks.push(c));
      req.on('end', () => {
        fs.mkdirSync(SHOTS, { recursive: true });
        fs.writeFileSync(path.join(SHOTS, name + (u.pathname === '/__shot' ? '.png' : '.json')), Buffer.concat(chunks));
        res.writeHead(200, { 'Content-Type': 'text/plain' }); res.end('ok');
      });
      return;
    }
    if (req.method === 'POST' && u.pathname === '/__bye') {      // 网页离开时报一声，当作掉线处理
      hub.dropToken(String(u.searchParams.get('token') || ''));
      res.writeHead(204); res.end();
      return;
    }
    let p = decodeURIComponent(u.pathname);
    if (p === '/') p = '/index.html';
    const file = path.join(WEB, p);
    if (!file.startsWith(WEB) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) { res.writeHead(404); res.end('not found'); return; }
    const ext = path.extname(file), head: Record<string, string | number> = { 'Content-Type': MIME[ext] || 'application/octet-stream', 'Cache-Control': 'no-cache' };
    let body = fs.readFileSync(file);
    if (/gzip/.test(String(req.headers['accept-encoding'] || '')) && ['.js', '.wasm', '.pck', '.html'].includes(ext)) {
      const key = file + fs.statSync(file).mtimeMs;
      if (!gz.has(key)) gz.set(key, zlib.gzipSync(body, { level: 6 }));
      body = gz.get(key)!; head['Content-Encoding'] = 'gzip';
    }
    head['Content-Length'] = body.length;
    res.writeHead(200, head); res.end(body);
  });

  server.on('upgrade', (req: any, sock: any) => {
    const conn: Conn & { sock: ReturnType<typeof acceptWs> } = {
      token: crypto.randomBytes(9).toString('hex'), room: null, sock: null,
      send(o) { this.sock?.send(o); },
      close() { this.sock?.close(); },
    };
    conn.sock = acceptWs(req, sock, m => hub.onMsg(conn, m), () => hub.leave(conn));
  });

  let last = Date.now();
  const timer = setInterval(() => {
    const now = Date.now(), dt = Math.min(0.1, (now - last) / 1000); last = now;
    hub.tick(dt, now);
  }, 33);

  return new Promise<{ hub: Hub; port: number; close: () => Promise<void> }>(resolve => {
    server.listen(port, host, () => {
      const real = (server.address() as { port: number }).port;
      resolve({ hub, port: real, close: () => new Promise<void>(r => { clearInterval(timer); server.closeAllConnections?.(); server.close(() => r()); }) });
    });
  });
}

// 直接运行这个文件时启动服务端；被测试引入时不启动
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const port = Number(process.env.PORT || process.argv[2]) || 8060, host = process.env.HOST || '127.0.0.1';
  startServer(port, host).then(s => {
    console.log(`深井夺金服务端已启动：http://localhost:${s.port}/`);
    if (host === '127.0.0.1') console.log('只允许本机访问。要让同一 WiFi 的设备进来，用 HOST=0.0.0.0 重新启动。');
  });
}
