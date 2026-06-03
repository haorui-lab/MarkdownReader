#!/bin/bash
# 一键构建 + 打包 MarkdownReader.dmg
# 用法: ./package.sh [--arch arm64|x86_64]
#   不指定 --arch 时同时构建两个架构
set -euo pipefail
cd "$(dirname "$0")"

build_dmg() {
    local ARCH="$1"
    local DMG_NAME="MarkdownReader-${ARCH}.dmg"

    echo ""
    echo "=========================================="
    echo "  构建 ${ARCH} 版本"
    echo "=========================================="

    # 1. 构建并签名
    ./build-app.sh --release --sign --arch "$ARCH"

    # 2. 打包 DMG
    STAGING=$(mktemp -d)
    trap "rm -rf '$STAGING'" EXIT
    cp -R MarkdownReader.app "$STAGING/"
    ln -s /Applications "$STAGING/Applications"
    hdiutil create -volname "Markdown Reader" -srcfolder "$STAGING" -ov -format UDZO "$DMG_NAME"

    # 3. 移除 quarantine 属性
    xattr -cr "$DMG_NAME" 2>/dev/null || true

    # 4. 验证
    echo "🔍 验证构建结果..."
    file MarkdownReader.app/Contents/MacOS/MarkdownReader
    codesign --verify --deep --strict MarkdownReader.app 2>&1 || true

    echo ""
    echo "✅ ${DMG_NAME} 已生成"

    # 清理临时目录
    rm -rf "$STAGING"
    trap - EXIT
}

# 解析参数
TARGET_ARCH=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --arch)
            TARGET_ARCH="$2"
            shift
            ;;
        *) echo "未知选项: $1"; exit 1 ;;
    esac
    shift
done

if [[ -n "$TARGET_ARCH" ]]; then
    # 只构建指定架构
    build_dmg "$TARGET_ARCH"
else
    # 同时构建两个架构
    build_dmg "arm64"
    build_dmg "x86_64"
fi

echo ""
echo "🎉 所有 DMG 打包完成！"
ls -lh MarkdownReader-*.dmg 2>/dev/null
