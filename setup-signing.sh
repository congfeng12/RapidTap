#!/bin/bash
#
# 创建本地稳定签名身份（只需执行一次）
#
# 背景：
#   ad-hoc 签名（codesign --sign -）的"指定要求"是 cdhash，每次重新编译都会变化，
#   macOS 会因此认为是一个新程序，之前授予的"辅助功能"权限随之失效。
#   使用固定的自签名证书后，指定要求变成 identifier + 证书指纹，重新编译也保持不变，
#   系统授权可以一直沿用。
#
set -euo pipefail

cd "$(dirname "$0")"

IDENTITY="RapidTap Local Signer"
KEYCHAIN="$HOME/Library/Keychains/rapidtap-signing.keychain-db"
KEYCHAIN_PASSWORD="rapidtap-build"

if [ -f "$KEYCHAIN" ] && security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null | grep -q "$IDENTITY"; then
    echo "==> 本地签名身份已存在：${IDENTITY}"
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

cat > "${WORK}/openssl.cnf" <<'EOF'
[ req ]
distinguished_name = dn
x509_extensions = ext
prompt = no
[ dn ]
CN = RapidTap Local Signer
[ ext ]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:false
EOF

echo "==> 生成本地自签名证书"
openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "${WORK}/key.pem" \
    -out "${WORK}/cert.pem" \
    -days 3650 \
    -config "${WORK}/openssl.cnf" >/dev/null 2>&1

# macOS 的 Security 框架只接受传统 PBE 的 PKCS#12，否则会报 MAC verification failed
openssl pkcs12 -export \
    -inkey "${WORK}/key.pem" \
    -in "${WORK}/cert.pem" \
    -out "${WORK}/id.p12" \
    -passout pass:"${KEYCHAIN_PASSWORD}" \
    -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1 2>/dev/null

echo "==> 导入专用钥匙串：${KEYCHAIN}"
security create-keychain -p "${KEYCHAIN_PASSWORD}" "${KEYCHAIN}" 2>/dev/null || true
security unlock-keychain -p "${KEYCHAIN_PASSWORD}" "${KEYCHAIN}"
security import "${WORK}/id.p12" -k "${KEYCHAIN}" -P "${KEYCHAIN_PASSWORD}" -T /usr/bin/codesign >/dev/null
# 允许 codesign 无交互使用私钥
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "${KEYCHAIN_PASSWORD}" "${KEYCHAIN}" >/dev/null

if security find-identity -p codesigning "${KEYCHAIN}" 2>/dev/null | grep -q "${IDENTITY}"; then
    echo "==> 完成"
    echo "    签名身份：${IDENTITY}"
    echo "    钥匙串  ：${KEYCHAIN}"
    echo "    作用    ：重新编译后应用签名保持不变，辅助功能授权不会失效"
    echo "    删除    ：security delete-keychain \"${KEYCHAIN}\""
else
    echo "!! 创建失败，可继续使用 ad-hoc 签名（重新编译后需重新授权）" >&2
    exit 1
fi
