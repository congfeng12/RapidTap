#!/bin/bash
#
# 编译 RapidTap 并打包为 .app
# 依赖：macOS 命令行工具（xcrun swiftc）
#
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="RapidTap"
BUNDLE="${APP_NAME}.app"
MIN_MACOS="13.0"
ARCH="$(uname -m)"
IDENTITY="RapidTap Local Signer"
KEYCHAIN="$HOME/Library/Keychains/rapidtap-signing.keychain-db"
KEYCHAIN_PASSWORD="rapidtap-build"

echo "==> 清理旧产物"
rm -rf "${BUNDLE}"

echo "==> 准备应用包结构"
mkdir -p "${BUNDLE}/Contents/MacOS" "${BUNDLE}/Contents/Resources"
cp Resources/Info.plist "${BUNDLE}/Contents/Info.plist"
cp Resources/AppIcon.icns "${BUNDLE}/Contents/Resources/AppIcon.icns"

echo "==> 编译（${ARCH} / macOS ${MIN_MACOS}+）"
xcrun swiftc \
    -swift-version 5 \
    -O \
    -target "${ARCH}-apple-macosx${MIN_MACOS}" \
    -framework Cocoa \
    -framework ApplicationServices \
    Sources/*.swift \
    -o "${BUNDLE}/Contents/MacOS/${APP_NAME}"

echo "==> 代码签名"
if [ -f "${KEYCHAIN}" ] && security find-identity -p codesigning "${KEYCHAIN}" 2>/dev/null | grep -q "${IDENTITY}"; then
    # 稳定签名身份：指定要求是 identifier + 证书指纹，重新编译也不会让系统授权失效
    security unlock-keychain -p "${KEYCHAIN_PASSWORD}" "${KEYCHAIN}" >/dev/null 2>&1 || true
    if codesign --force --keychain "${KEYCHAIN}" --sign "${IDENTITY}" \
        --identifier "com.rapidtap.mac" "${BUNDLE}" 2>/dev/null; then
        echo "    使用本地稳定签名身份：${IDENTITY}"
        echo "    重新编译后系统授权仍然有效"
    else
        codesign --force --sign - --identifier "com.rapidtap.mac" "${BUNDLE}" 2>/dev/null || true
        echo "    稳定签名失败，已回退 ad-hoc；重新编译后需要重新授权"
    fi
else
    codesign --force --sign - --identifier "com.rapidtap.mac" "${BUNDLE}" 2>/dev/null || true
    echo "    ad-hoc 签名：重新编译后需要重新授予辅助功能权限"
    echo "    可先执行 ./setup-signing.sh 创建本地稳定签名身份（只需一次）"
fi

echo "==> 完成：$(pwd)/${BUNDLE}"
echo "    启动：./run.sh  或  open ${BUNDLE}"
