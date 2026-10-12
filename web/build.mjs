import { build } from 'esbuild'
import { cpSync, mkdirSync, rmSync } from 'node:fs'

const outdir = 'dist'

rmSync(outdir, { recursive: true, force: true })
mkdirSync(outdir, { recursive: true })

await build({
    entryPoints: ['src/main.js'],
    bundle: true,
    outfile: `${outdir}/bundle.js`,
    format: 'iife',
    target: ['safari16.4'],
    platform: 'browser',
    minify: false,
    sourcemap: false,
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
