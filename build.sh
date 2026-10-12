#!/bin/bash
# MDPreview 一键构建:web 资源打包 + Swift 编译 + 组装 .app
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"
echo "==> [1/3] 构建前端资源 (esbuild)"
(
    cd web
    if [ ! -d node_modules ]; then
        npm install --registry=https://registry.npmmirror.com --no-audit --no-fund --cache ./.npm-cache
    fi
    node build.mjs
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
if [ -f resources/AppIcon.icns ]; then
    cp resources/AppIcon.icns "$APP/Contents/Resources/"
fi
codesign --force --sign - "$APP" 2>/dev/null || true

echo "完成: $APP"
echo "运行: open '$APP' --args <markdown 文件路径>"
