// 三个平台共用的启动器。服务端保留在启动窗口的进程组里。
import { spawn } from 'node:child_process';
import { existsSync } from 'node:fs';
import { createServer, isIP } from 'node:net';
import { setTimeout as wait } from 'node:timers/promises';

function portIsFree(port, host) {
    return new Promise((resolve, reject) => {
        const probe = createServer(socket => socket.destroy());
        probe.once('error', error => {
            if (error.code === 'EADDRINUSE') resolve(false);
            else reject(error);
        });
        probe.listen(port, host, () => probe.close(() => resolve(true)));
    });
}

function openBrowser(url) {
    const command = process.platform === 'win32' ? 'cmd.exe' : process.platform === 'darwin' ? 'open' : 'xdg-open';
    const args = process.platform === 'win32' ? ['/d', '/c', 'start', '', url] : [url];
    const opener = spawn(command, args, { stdio: 'ignore', windowsHide: true });
    opener.on('error', () => console.error(`请在浏览器手动打开 ${url}`));
    opener.unref();
}

async function waitForPage(url, signal) {
    const deadline = Date.now() + 10000;
    while (!signal.aborted && Date.now() < deadline) {
        const attempt = AbortSignal.any([signal, AbortSignal.timeout(400)]);
        const response = await fetch(url, { method: 'HEAD', signal: attempt }).catch(() => null);
        if (response?.ok) return true;
        await wait(200, undefined, { signal }).catch(() => {});
    }
    return false;
}

async function launch() {
    const port = Number(process.env.PORT || '8060');
    const host = process.env.HOST || '127.0.0.1';
    if (!Number.isInteger(port) || port < 1 || port > 65535) {
        throw new Error('PORT 必须是 1 到 65535 之间的整数。');
    }
    // 通配地址用于监听，浏览器连接对应的本机回环地址。
    const probeHost = host === '0.0.0.0' ? '127.0.0.1' : host === '::' ? '::1' : host;
    const address = isIP(probeHost) === 6 ? `[${probeHost}]` : probeHost;
    if (!/^[a-z\d.:[\]_-]+$/i.test(address)) throw new Error('HOST 应为主机名或 IP 地址。');
    const browserHost = ['127.0.0.1', '::1', 'localhost'].includes(probeHost) ? 'localhost' : address;
    const page = `http://${browserHost}:${port}`;

    if (!await portIsFree(port, host)) {
        console.log(`可能已经开着一个了，直接打开 ${page}，或者先关掉那个窗口。`);
        openBrowser(page);
        return;
    }
    if (!existsSync('build/web/index.html')) {
        throw new Error('找不到网页版。请完整解压发布包，或在源码目录先导出网页版。');
    }

    const server = spawn(process.execPath, ['server/src/main.ts'], { stdio: 'inherit' });
    const lifetime = new AbortController();
    let stopping = false;
    const stop = () => {
        stopping = true;
        lifetime.abort();
        server.kill();
    };
    for (const signal of ['SIGINT', 'SIGTERM', 'SIGHUP']) process.on(signal, stop);

    const exited = new Promise(resolve => {
        server.once('exit', code => {
            lifetime.abort();
            resolve(code ?? 1);
        });
        server.once('error', error => {
            console.error(`无法启动服务端：${error.message}`);
            lifetime.abort();
            resolve(1);
        });
    });

    if (await waitForPage(`http://${address}:${port}/`, lifetime.signal)) {
        if (!lifetime.signal.aborted) {
            console.log(`游戏已启动：${page}。关掉这个窗口就会停止。`);
            openBrowser(page);
        }
    } else if (!lifetime.signal.aborted) {
        console.error('等了约 10 秒，网页仍无法访问。请查看服务端输出，再重新启动。');
        server.kill();
    }

    const code = await exited;
    process.exitCode = stopping ? 0 : code;
}

launch().catch(error => {
    console.error(`启动失败：${error.message}`);
    process.exitCode = 1;
});
