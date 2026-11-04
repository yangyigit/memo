#!/usr/bin/env bash
# 编译 Memo。按本机是否存在 Apple Development 证书，自动选择签名方式：
#   - 有证书 → Apple Development 签名（小组件才能被系统加载）
#   - 无证书 → ad-hoc 签名（App 可用，小组件不会出现在组件库）
set -uo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-Debug}"
DERIVED="build/DerivedData"
LOG="build/xcodebuild.log"
mkdir -p build

# 取第一个 Apple Development 证书的 SHA-1 身份（比名字更稳，不受重名/邮箱变化影响）
IDENTITY_HASH="${CODE_SIGN_HASH:-$(security find-identity -v -p codesigning 2>/dev/null \
  | sed -n 's/^ *[0-9]*) \([0-9A-F]\{40\}\).*Apple Development.*/\1/p' | head -1)}"

COMMON=(-project Memo.xcodeproj -scheme Memo -configuration "$CONFIG" -derivedDataPath "$DERIVED")

if [ -n "$IDENTITY_HASH" ]; then
  echo "🔏 签名模式：Apple Development（${IDENTITY_HASH:0:10}…）"
else
  echo "⚠️  ad-hoc 模式：未找到 Apple Development 证书 —— App 能跑，但系统不会加载小组件"
  echo "    需要小组件时：Xcode → Settings → Accounts 登录 Apple ID，然后重新 make run"
fi

# 签名参数统一由 scripts/signargs.sh 产出，保证 build 与 test 一致
mapfile -t SIGN < <(CODE_SIGN_HASH="${IDENTITY_HASH}" ./scripts/signargs.sh)

set -o pipefail
xcodebuild "${COMMON[@]}" "${SIGN[@]}" build 2>&1 | tee "$LOG" | grep -E "error:|^BUILD|^\*\*" || true

if grep -q "^\*\* BUILD SUCCEEDED" "$LOG"; then
  echo "✅ build ok ($CONFIG)"
else
  echo "❌ build failed —— 见 $LOG"
  exit 1
fi
