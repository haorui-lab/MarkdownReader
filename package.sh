#!/bin/bash
# 一键构建 + 打包 MarkdownReader.dmg
# 用法: ./package.sh
set -euo pipefail
cd "$(dirname "$0")"

# 1. 构建并签名
./build-app.sh --release --sign

# 2. 打包 DMG
STAGING=$(mktemp -d)
trap "rm -rf '$STAGING'" EXIT  # 确保临时目录即使出错也会被清理
cp -R MarkdownReader.app "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "Markdown Reader" -srcfolder "$STAGING" -ov -format UDZO MarkdownReader.dmg

# 3. 移除 quarantine 属性，避免传输后触发 Gatekeeper
xattr -cr MarkdownReader.dmg 2>/dev/null || true

# 4. 验证
echo "🔍 验证构建结果..."
file MarkdownReader.app/Contents/MacOS/MarkdownReader
codesign --verify --deep --strict MarkdownReader.app 2>&1 || true

echo ""
echo "✅ MarkdownReader.dmg 已生成"
echo "   发给朋友后，对方：双击 DMG → 拖到 Applications → 右键打开"
