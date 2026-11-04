import { build } from 'esbuild'
import { cpSync, mkdirSync, rmSync } from 'node:fs'

const outdir = 'dist'

rmSync(outdir, { recursive: true, force: true })
mkdirSync(outdir, { recursive: true })

await build({
    entryPoints: ['src/page.js'],
    bundle: true,
    outfile: `${outdir}/bundle.js`,
    format: 'iife',
    target: ['safari16.4'],
    platform: 'browser',
    // OQ-4 结论 a:生产压缩;本地 external sourcemap(生成 bundle.js.map 但不在
    // 产物里留 sourceMappingURL 引用,jserror 栈可离线符号化,分发时不随包带 map,
    // build.sh 组装 .app 时剔除 *.map)
    minify: true,
    sourcemap: 'external',
    legalComments: 'none',
    loader: {
        '.woff2': 'file',
        '.woff': 'file',
        '.ttf': 'file',
        '.eot': 'file',
        '.svg': 'file',
        '.png': 'file',
    },
    assetNames: 'assets/[name]',
    publicPath: '.',
    logLevel: 'info',
})

cpSync('src/index.html', `${outdir}/index.html`)
console.log('web build done →', outdir)
