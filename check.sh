#!/bin/bash
# 检查服务端代码的类型（只在开发时用，不影响运行）。需要先在 server/ 里装过 typescript：
#   cd server && npm install --registry https://registry.npmjs.org/ --ignore-scripts
cd "$(dirname "$0")/server"
if ./node_modules/.bin/tsc -p .; then echo "类型检查通过"; else echo "类型检查没过，见上面"; exit 1; fi
