#!/bin/bash
set -euo pipefail
version=0.3.0

cd "$(dirname "$0")/.."
mkdir -p dist
scratch=$(mktemp -d dist/.package.XXXXXX)
release="super-miner-$version"
trap 'rm -f "$scratch/export-start" "$scratch/$release.zip"; rmdir "$scratch"' EXIT
touch "$scratch/export-start"
./export.sh --only

# 标准库写入 UTF-8 文件名和 Unix 权限，Windows 解压时中文文件名也能识别。
python3 - "$scratch" "$release" <<'PYTHON'
import os
import re
import subprocess
import sys
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile

scratch, release = Path(sys.argv[1]), sys.argv[2]
export_time = (scratch / 'export-start').stat().st_mtime_ns
web = Path('build/web')
web_files = [web / name for name in (
    'index.html', 'index.js', 'index.wasm', 'index.pck',
    'index.audio.worklet.js', 'index.audio.position.worklet.js',
    'index.png', 'index.icon.png', 'index.apple-touch-icon.png',
)]
for file in web_files:
    # 导出脚本可能在失败时仍返回 0，检查本次实际写出的文件，避免打进旧版本。
    if not file.is_file() or file.stat().st_size == 0 or file.stat().st_mtime_ns <= export_time:
        sys.exit(f'导出缺少本次生成的文件：{file}')

excluded = {'raw', 'shots', '任务', 'node_modules', '.godot', '.tools', 'logs', 'test', '.DS_Store', '__MACOSX'}
files = web_files + [Path(name) for name in (
    'server/package.json', 'server/launch.mjs', 'start.command', 'start.sh', 'start.bat', '怎么运行.txt',
)]
for directory in (Path('server/src'), Path('shared')):
    files.extend(file for file in sorted(directory.rglob('*'))
                 if file.is_file() and not excluded.intersection(file.parts))

def git_config(key):
    try:
        result = subprocess.run(['git', 'config', '--get', key], capture_output=True)
    except FileNotFoundError:
        return b''
    return result.stdout.rstrip(b'\r\n') if result.returncode == 0 else b''


username = subprocess.check_output(['id', '-un']).rstrip(b'\r\n')
proxy_keys = ('ALL_PROXY', 'HTTP_PROXY', 'HTTPS_PROXY', 'all_proxy', 'http_proxy', 'https_proxy')
private_values = (
    ('主目录路径', [os.fsencode(os.environ.get('HOME', ''))]),
    ('本机用户名路径', [b'/' + username + b'/', b'\\' + username + b'\\']),
    ('Git 邮箱', [git_config('user.email')]),
    ('Git 姓名', [git_config('user.name')]),
    ('代理地址', [os.fsencode(os.environ.get(key, '')) for key in proxy_keys]),
)
local_path = re.compile(rb'/(?:Users|private/tmp)/|[a-z]:\\Users\\', re.IGNORECASE)
for file in files:
    if file.is_symlink():
        sys.exit(f'发布包中的文件必须是普通文件：{file}')
    data = file.read_bytes()
    for kind, values in private_values:
        if any(value and value in data for value in values):
            sys.exit(f'发布包隐私检查未通过：{file}（命中{kind}）')
    if local_path.search(data):
        sys.exit(f'发布包隐私检查未通过：{file}（命中本机路径前缀）')

temporary = scratch / f'{release}.zip'
destination = Path('dist') / temporary.name
with ZipFile(temporary, 'w', compression=ZIP_DEFLATED) as archive:
    for file in files:
        archive.write(file, f'{release}/{file.as_posix()}')
temporary.replace(destination)
size = destination.stat().st_size
print(f'发布包：{destination}（{size:,} 字节，{size / 1024**2:.1f} MiB，共 {len(files)} 个文件）')
PYTHON
