#!/usr/bin/env bash
# 输出 xcodebuild 需要的签名参数（一行一个，供 make 使用）
#   - 有 Apple Development 证书 → 用它签名（小组件才能被系统加载）
#   - 没有 → 退回 ad-hoc
set -uo pipefail
HASH="${CODE_SIGN_HASH:-$(security find-identity -v -p codesigning 2>/dev/null \
  | sed -n 's/^ *[0-9]*) \([0-9A-F]\{40\}\).*Apple Development.*/\1/p' | head -1)}"

if [ -n "$HASH" ]; then
  echo "CODE_SIGN_STYLE=Manual"
  echo "CODE_SIGN_IDENTITY=$HASH"
  echo "CODE_SIGNING_REQUIRED=YES"
else
  echo "CODE_SIGN_STYLE=Manual"
  echo "CODE_SIGN_IDENTITY=-"
  echo "CODE_SIGNING_REQUIRED=YES"
fi
