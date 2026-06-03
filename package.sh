#!/bin/bash
# 一键构建 + 打包 MarkdownReader.dmg
# 用法: ./package.sh
set -e
cd "$(dirname "$0")"

# 1. 构建并签名
./build-app.sh --release --sign

# 2. 打包 DMG
STAGING=$(mktemp -d)
cp -R MarkdownReader.app "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "Markdown Reader" -srcfolder "$STAGING" -ov -format UDZO MarkdownReader.dmg
rm -rf "$STAGING"

# 3. 移除 quarantine 属性，避免微信等传输后触发 Gatekeeper
# 注意：这只会移除本地文件的 quarantine，接收方下载后仍可能有自己的 quarantine
# 但对于 ad-hoc 签名的应用，右键打开即可绕过
xattr -d com.apple.quarantine MarkdownReader.dmg 2>/dev/null || true

echo ""
echo "✅ MarkdownReader.dmg 已生成"
echo "   发给朋友后，对方：双击 DMG → 拖到 Applications → 右键打开"
