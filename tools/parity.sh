#!/usr/bin/env bash
# 双目标 parity 门禁（T-W9-3）：wasm / native 测试总数与通过数必须一致。
# 自包含：仅依赖本仓库与 moon CLI，不引用仓库外路径。
set -euo pipefail
cd "$(dirname "$0")/.."

# WSL interop 兼容：无 moon 时回退 moon.exe。
MOON="${MOON:-moon}"
command -v "$MOON" >/dev/null 2>&1 || MOON=moon.exe

wasm_out="$("$MOON" test --target wasm 2>&1 | grep -E '^Total tests:' || true)"
native_out="$("$MOON" test --target native 2>&1 | grep -E '^Total tests:' || true)"
echo "wasm:   ${wasm_out:-<no summary>}"
echo "native: ${native_out:-<no summary>}"

if [ -z "$wasm_out" ] || [ -z "$native_out" ]; then
  echo "parity FAIL: missing test summary" >&2
  exit 1
fi
echo "$wasm_out" | grep -q "failed: 0" || { echo "parity FAIL: wasm has failures" >&2; exit 1; }
echo "$native_out" | grep -q "failed: 0" || { echo "parity FAIL: native has failures" >&2; exit 1; }
if [ "$wasm_out" != "$native_out" ]; then
  echo "parity FAIL: wasm/native summary differs" >&2
  exit 1
fi
echo "parity OK: $wasm_out"