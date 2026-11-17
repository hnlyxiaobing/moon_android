#!/usr/bin/env bash
# 引用实存性 + README 索引 + 错误簿记门禁（T-W9-4 / W1 漂移回归）。
# 1) 源码/CI 中引用的 docs/*.md 必须实存（悬空引用即红）；
# 2) pkg.generated.mbti 的每个 pub fn 必须出现在 README.md 索引；
# 3) 14 个错误变体必须在测试文件中有触发/断言承载（MissingGate 单列：
#    保留变体，允许仅白盒人工 raise 承载）。
# 自包含：仅扫描本仓库文件。
set -euo pipefail
cd "$(dirname "$0")/.."

fail=0

# 1) 悬空 docs 引用。
refs="$(grep -rEoh 'docs/[A-Za-z0-9_.-]+\.md' --include='*.mbt' --include='*.yml' . | sort -u || true)"
for ref in $refs; do
  if [ ! -f "$ref" ]; then
    echo "ref-scan FAIL: dangling reference $ref" >&2
    fail=1
  fi
done
echo "ref-scan: docs references checked ($(echo "$refs" | grep -c . || true) unique)"

# 2) README 索引核对（pub fn，排除方法行）。
fns="$(grep -E '^pub fn [a-z]' pkg.generated.mbti | sed -E 's/^pub fn ([A-Za-z0-9_]+).*/\1/')"
for fn in $fns; do
  if ! grep -q "$fn" README.md; then
    echo "ref-scan FAIL: pub fn $fn missing from README.md index" >&2
    fail=1
  fi
done
echo "ref-scan: README index checked ($(echo "$fns" | grep -c .) pub fns)"

# 3) 错误簿记 14/14。
variants="$(sed -n '/pub suberror MoonAndroidError/,/^}/p' pkg.generated.mbti | grep -E '^  [A-Z]' | sed -E 's/^  ([A-Za-z0-9_]+).*/\1/')"
count=0
for v in $variants; do
  count=$((count + 1))
  if ! grep -rq "$v" --include='*_test.mbt' --include='*_wbtest.mbt' .; then
    echo "ref-scan FAIL: error variant $v has no test coverage" >&2
    fail=1
  fi
done
echo "ref-scan: error ledger $count/14 variants covered"
if [ "$count" -ne 14 ]; then
  echo "ref-scan FAIL: expected 14 variants, found $count" >&2
  fail=1
fi

if [ "$fail" -ne 0 ]; then
  exit 1
fi
echo "ref-scan OK"