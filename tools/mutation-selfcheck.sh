#!/usr/bin/env bash
# 变异自检门禁（T-W9-2）：3 类缺陷注入必须使测试变红，还原后复绿。
# 缺陷 1：移除渲染头 set -eu（W2 fail-closed 回归）
# 缺陷 2：V31 轮换标记失效（W3 签名保真回归）
# 缺陷 3：jdk_major 位数上限失效（W6 溢出防护回归）
# 自包含：备份用 mktemp，trap 保证任何退出路径都还原源码。
set -euo pipefail
cd "$(dirname "$0")/.."

# WSL interop 兼容：无 moon 时回退 moon.exe。
MOON="${MOON:-moon}"
command -v "$MOON" >/dev/null 2>&1 || MOON=moon.exe

tmp="$(mktemp -d)"
cp moon_android.mbt "$tmp/moon_android.mbt.bak"
cp jdk.mbt "$tmp/jdk.mbt.bak"
restore_files() {
  cp "$tmp/moon_android.mbt.bak" moon_android.mbt
  cp "$tmp/jdk.mbt.bak" jdk.mbt
}
cleanup() {
  restore_files
  rm -rf "$tmp"
}
trap cleanup EXIT

expect_red() {
  local label="$1"
  if "$MOON" test >"$tmp/mutation.log" 2>&1; then
    echo "mutation-selfcheck FAIL: $label survived (tests stayed green)" >&2
    exit 1
  fi
  echo "mutation-selfcheck OK: $label turned tests red"
  restore_files
}

# 缺陷 1：set -eu 头消失。
sed -i 's|#!/bin/sh\\nset -eu\\n|#!/bin/sh\\n|' moon_android.mbt
expect_red "defect-1 remove set -eu"

# 缺陷 2：V31 轮换标记失效。
sed -i 's|has_v31 = true|has_v31 = false|' moon_android.mbt
expect_red "defect-2 disable V31 rotation marker"

# 缺陷 3：位数上限失效。
sed -i 's|if first_digits > 9 {|if false {|' jdk.mbt
expect_red "defect-3 disable digit cap"

# 还原后必须复绿。
if ! "$MOON" test >"$tmp/final.log" 2>&1; then
  echo "mutation-selfcheck FAIL: suite not green after restore" >&2
  cat "$tmp/final.log" >&2
  exit 1
fi
grep -E '^Total tests:' "$tmp/final.log"
echo "mutation-selfcheck OK: 3/3 defects detected, suite green after restore"