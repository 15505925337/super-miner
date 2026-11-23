// Node 自带模块的简易声明。没有装 @types/node（那要再装两个包），所以这里把用到的 Node 接口都当成"任意类型"。
// 结果是：我们自己的规则代码（core / game / shop / fun / rooms）有完整的类型检查，调用 Node 接口的地方只检查名字、不检查参数。
declare module 'node:fs' { const x: any; export default x; export const readFileSync: any, writeFileSync: any, mkdirSync: any, existsSync: any, statSync: any, readdirSync: any, mkdtempSync: any, rmSync: any; }
declare module 'node:path' { const x: any; export default x; export const join: any, resolve: any, dirname: any, extname: any; }
declare module 'node:os' { const x: any; export default x; }
declare module 'node:http' { const x: any; export default x; export type IncomingMessage = any; }
declare module 'node:stream' { export type Duplex = any; }
declare module 'node:zlib' { const x: any; export default x; }
declare module 'node:crypto' { const x: any; export default x; export const createHash: any; }
declare module 'node:url' { export const fileURLToPath: any; }
declare module 'node:net' { const x: any; export default x; }
declare module 'node:test' { const test: any; export default test; }
declare module 'node:assert/strict' { const assert: any; export default assert; }
declare const process: any;
declare const Buffer: any;
type Buffer = any;
interface ImportMeta { url: string; main?: boolean }
