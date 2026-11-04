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

TEAM_ID="${TEAM_ID:-$(security find-identity -v -p codesigning 2>/dev/null \
  | sed -n 's/.*Apple Development[^(]*(\([A-Z0-9]*\)).*/\1/p' | head -1)}"

COMMON=(-project Memo.xcodeproj -scheme Memo -configuration "$CONFIG" -derivedDataPath "$DERIVED")

if [ -n "$TEAM_ID" ]; then
  echo "🔏 签名模式：Apple Development（team $TEAM_ID）"
  SIGN=(-allowProvisioningUpdates
        DEVELOPMENT_TEAM="$TEAM_ID"
        CODE_SIGN_STYLE=Automatic
        CODE_SIGN_IDENTITY="Apple Development")
else
  echo "⚠️  ad-hoc 模式：未找到 Apple Development 证书 —— App 能跑，但系统不会加载小组件"
  echo "    需要小组件时：Xcode → Settings → Accounts 登录 Apple ID，然后重新 make run"
  SIGN=(CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=YES)
fi

set -o pipefail
xcodebuild "${COMMON[@]}" "${SIGN[@]}" build 2>&1 | tee "$LOG" | grep -E "error:|warning: .*entitlement|^BUILD|^\*\*" || true

if grep -q "^\*\* BUILD SUCCEEDED" "$LOG"; then
  echo "✅ build ok ($CONFIG)"
else
  echo "❌ build failed —— 见 $LOG"
  exit 1
fi
