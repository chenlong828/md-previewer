#!/bin/bash
# MDPreview 一键构建:web 资源打包 + Swift 编译 + 组装 .app
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"
# npm 源可环境变量覆盖(默认 npmmirror;离线/内网场景设 NPM_REGISTRY 即可)
NPM_REGISTRY="${NPM_REGISTRY:-https://registry.npmmirror.com}"
echo "==> [1/3] 构建前端资源 (esbuild)"
(
    cd web
    if [ ! -d node_modules ]; then
        npm install --registry="$NPM_REGISTRY" --no-audit --no-fund --cache ./.npm-cache
    fi
    node build.mjs
    # 内核分层禁边 + 契约套件(纯 Node,不依赖 WebView):门禁失败即中断构建
    node check-kernel.mjs
    node --test test/
)

echo "==> [2/3] 编译 Swift ($CONFIG)"
BUILD_FLAGS=(--disable-sandbox --manifest-cache none --cache-path ./.spm-cache)
if [ -n "${SWIFTPM_MODULECACHE_OVERRIDE:-}" ]; then :; else
    export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.modulecache"
fi
swift build -c "$CONFIG" "${BUILD_FLAGS[@]}"

echo "==> [3/3] 组装 MDPreview.app"
APP="dist/MDPreview.app"
BIN_PATH="$(swift build -c "$CONFIG" "${BUILD_FLAGS[@]}" --show-bin-path)"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/web"
cp "$BIN_PATH/MDPreview" "$APP/Contents/MacOS/"
cp resources/Info.plist "$APP/Contents/"
cp -R web/dist/* "$APP/Contents/Resources/web/"
# sourcemap 只留在仓库本地供 jserror 离线符号化,不随 .app 分发(OQ-4 结论 a)
find "$APP/Contents/Resources/web" -name '*.map' -delete
if [ -f resources/AppIcon.icns ]; then
    cp resources/AppIcon.icns "$APP/Contents/Resources/"
fi
# ad-hoc 签名失败必须中断构建(吞掉失败会产出无法启动的 .app)
codesign --force --sign - "$APP"

echo "完成: $APP"
echo "运行: open '$APP' --args <markdown 文件路径>"
