#!/usr/bin/env python3
"""只从远端 zip（比如 Godot 的导出模板 .tpz）里取指定的几个文件，不下载整包。
用法：
  remote_zip.py <url> list                 列出包里的文件和大小
  remote_zip.py <url> get <目标目录> <包内文件名> [<包内文件名> ...]
只用标准库。靠 HTTP Range 分段读取。"""
import io, os, sys, urllib.request, zipfile


class RangeFile(io.RawIOBase):
    def __init__(self, url):
        self.url = url
        req = urllib.request.Request(url, method="HEAD")
        with urllib.request.urlopen(req, timeout=60) as r:
            self.url = r.geturl()            # 跟随跳转后的真实地址
            self.size = int(r.headers["Content-Length"])
        self.pos = 0
        self.fetched = 0

    def seekable(self): return True
    def readable(self): return True
    def tell(self): return self.pos

    def seek(self, off, whence=0):
        self.pos = off if whence == 0 else (self.pos + off if whence == 1 else self.size + off)
        return self.pos

    def read(self, n=-1):
        if n < 0: n = self.size - self.pos
        if n == 0 or self.pos >= self.size: return b""
        end = min(self.size, self.pos + n) - 1
        req = urllib.request.Request(self.url, headers={"Range": "bytes=%d-%d" % (self.pos, end)})
        with urllib.request.urlopen(req, timeout=300) as r:
            if r.status != 206: raise IOError("服务器不支持分段下载，状态码 %s" % r.status)
            data = r.read()
        self.pos += len(data); self.fetched += len(data)
        return data

    def readinto(self, b):
        d = self.read(len(b)); b[:len(d)] = d; return len(d)


def main():
    url, cmd = sys.argv[1], sys.argv[2]
    rf = RangeFile(url)
    zf = zipfile.ZipFile(io.BufferedReader(rf, buffer_size=1 << 20))
    if cmd == "list":
        for i in zf.infolist():
            print("%10.1f MB  %s" % (i.compress_size / 1e6, i.filename))
        print("整包 %.1f MB，本次只读了 %.2f MB" % (rf.size / 1e6, rf.fetched / 1e6))
        return
    out = sys.argv[3]; os.makedirs(out, exist_ok=True)
    for name in sys.argv[4:]:
        info = zf.getinfo(name)
        dst = os.path.join(out, os.path.basename(name))
        with zf.open(info) as src, open(dst, "wb") as f:
            while True:
                chunk = src.read(1 << 20)
                if not chunk: break
                f.write(chunk)
        print("已取出 %s  %.1f MB" % (dst, os.path.getsize(dst) / 1e6))
    print("整包 %.1f MB，本次只下载了 %.1f MB" % (rf.size / 1e6, rf.fetched / 1e6))


if __name__ == "__main__":
    main()
