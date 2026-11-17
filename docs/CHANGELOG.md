# CHANGELOG

> 簿记规则：每工作包登记「日期 / 工作包 / 新增 pub 声明 / 快照 diff 结论 / 测试增量 / fail-closed 或 golden 重录裁决记录」。
> 设计依据：[2026-11-16-packaging-plan-fidelity-dev-plan.md](2026-11-16-packaging-plan-fidelity-dev-plan.md)。

## 2026-11-16 · W1 漂移清理与簿记建立

- 新增 pub 声明：无。
- 快照 diff：零（纯文档/注释包）。
- 变更：
  - 修复 HEAD f304de0 删除 docs/ 后遗留的 7 处悬空引用：`template.mbt`（2 处 docs/TEMPLATE.md）、`jdk.mbt`（docs/EXECUTION-CHAIN.md）、`moon_android_test.mbt`（docs/DECISIONS.md）、`ci.yml`（3 处 docs/DECISIONS.md / docs/API.md），全部改指 README.md 对应章节。
  - README §3 API 索引补 `pub trait BuildPlanner`（此前漏列）；§1 修正 InvalidStepOrder 可达性措辞（仅渲染入口对任意计划强制）；§1 补 verify_artifact 实际语义（size/sha256 仅规格检查）；§2 声明 MissingGate 保留变体与 ci_gate_plan 建议序列性质；首行「唯一说明文档」改为「唯一说明文档 + docs/ 设计文档与 CHANGELOG」。
  - `template.mbt` valid_module_dep 注释样例坐标中性化（author/name 形式；测试字面量与 golden 不动）。
  - 建立本 CHANGELOG。
- 测试增量：0（基线 79/79 保持）。
- 裁决记录：无需（零行为变化）。

## 2026-11-16 · W2 渲染脚本 fail-closed（set -eu）

- 新增 pub 声明：无（`script_header()` 为私有共用头）。
- 快照 diff：零。
- 变更：`render_script` / `render_template_script` 输出头由 `#!/bin/sh` 改为 `#!/bin/sh` + `set -eu`；资产阶段 `sha256sum -c` 校验失败后不再继续复制（fail-closed）。
- 测试增量：+3（render_script 头部、render_template_script 头部先于一切命令、校验行先于复制行）。
- 裁决记录：**golden 书面重录**——2026-11-16 用户「采纳推荐」批准 W2-A；`moon test --update` 重录两处 golden，diff 审阅确认仅限裁决行（新增 `set -eu` 一行），其余输出逐字节不变。

## 2026-11-16 · W3 apksigner 命令保真

- 新增 pub 声明：无。
- 快照 diff：零。
- 变更：删除官方不存在的 `--v31-signing-enabled` 伪 flag；V31 scheme 渲染为轮换语义注释 + `--v3-signing-enabled true`（仅 V31 的手工商议计划也伴生 v3 flag）；命令尾显式追加 `--min-sdk-version` / `--max-sdk-version`。
- 测试增量：+3（官方 flag 面、V31 轮换注释、仅 V31 伴生 v3）。
- 裁决记录：**golden 书面重录**——2026-11-16 用户「采纳推荐」批准 W3-A；重录 diff 仅限 apksigner 命令行裁决行。防火墙确认：旧负例/错误路径用例零改动全绿。

## 2026-11-16 · W6 jdk_major 溢出防护

- 新增 pub 声明：无。
- 快照 diff：零。
- 变更：`jdk_major` 每段数字限 9 位（1.x 第二段同限），超限返回 None，防 Int32 回绕伪匹配（如 4294967313.0.1 不得匹配 17）。
- 测试增量：+2（白盒位数矩阵 + 黑盒回绕版本号）。
- 裁决记录：**fail-closed 修复例外**——旧行为（回绕伪匹配）属缺陷而非契约；回归确认旧用例零改动全绿，新增负例锁定 None 语义。

## 2026-11-16 · W4 值化配置校验（check_sdk_range / check_entry_url）

- 新增 pub 声明：`pub fn check_sdk_range(BuildConfig) -> SdkRangeReport`、`pub fn check_entry_url(BuildConfig) -> EntryUrlReport`、`pub(all) struct SdkRangeReport`、`pub(all) struct EntryUrlReport`。
- 快照 diff：+4 fn/struct 行，纯加法，零删除零修改。
- 变更：新文件 `config_check.mbt`（零 raise，报告值化）；SDK 范围 1..=100 宽松健全上界 + min≤target；WebView 入口 URL 必填且 scheme ∈ http/https/file（大小写不敏感）。`plan_build` 放行行为不变，调用方据报告自行拒绝。
- 测试增量：+3（含防火墙测试：min_sdk=-5 配 V1+V2 时 plan_build 行为逐字节不变）。
- 裁决记录：无需（纯加法新入口，不改旧 API）。

## 2026-11-16 · W5 plan_extra_native_libs 接线

- 新增 pub 声明：`pub fn plan_extra_native_libs(Array[String], Array[Abi]) -> Array[NativeLib] raise MoonAndroidError`。
- 快照 diff：+1 fn 行，纯加法。
- 变更：sonames×abis 按序 zip 产出 `NativeLib`（sha256=None）；坏 soname / 重复 / 长度不一致 / 空重复 ABI 均抛 `InvalidNativeLib`。组合根消费，`plan_build` 不自动入包（W5-A 裁决）。
- 测试增量：+4（双 ABI 布局、坏输入矩阵、attach/validate/render 互操作全链、防火墙——plan_build 渲染逐字不变）。
- 裁决记录：2026-11-16 用户「采纳推荐」批准 W5-A（纯加法接线，不改 plan_build 语义）。

## 2026-11-16 · W7 probe_jdk_strict（fail-closed 替代入口）

- 新增 pub 声明：`pub fn probe_jdk_strict(JdkProbeEnv) -> JdkProbeResult raise MoonAndroidError`。
- 快照 diff：+1 fn 行，纯加法。
- 变更：提取 `probe_jdk_impl(env, strict)` 共用实现；`probe_jdk` 语义逐字节不变（version=None fail-open 为明示设计）；strict 下 version=None 候选不选中并记诊断，版本齐备候选结论与非 strict 逐字一致。
- 测试增量：+4（strict 拒绝 None、齐备双语义一致、跳过无版本候选选中后续、required_major 越界复用 InvalidJdkProbe）。
- 裁决记录：无需（纯加法；旧入口行为不变，防火墙测试锁定）。

## 2026-11-16 · W8 薄 CLI（gates / render / template / probe-jdk）

- 新增 pub 声明：库快照零变化；`cmd/main/pkg.generated.mbti` +1 行 `type Flags`（可执行包内部 struct，纯加法）。
- 变更：`cmd/main/main.mbt` 由 Hello 示例改为薄 CLI（约 440 行）：退出码契约 0=成功 / 1=库校验失败（stderr 输出错误变体名，stdout 不泄漏密钥）/ 2=用法错误；内置 locked_toolchain 与测试夹具同值；`cmd/main/moon.pkg` 启用 import。
- 测试增量：0（库测试不变）；实跑验收 `tools/cli-smoke.ps1` **13/13 PASS**（fmt 后复跑确认）。
- 裁决记录：2026-11-16 用户「采纳推荐」批准 W8-A（薄 CLI，不引入新依赖）。

## 2026-11-16 · W9 性质测试 + 变异语料 + 门禁脚本

- 新增 pub 声明：无。
- 快照 diff：零。
- 变更：
  - `properties_test.mbt`：P1/P4/P5/P6/P8/P9/P10 七条性质测试（确定性、XML 五字符转义、lib/ 布局计数、heredoc 界标恰 2 次、特殊字符 app_name/entry_url 转义落点等）。
  - `mutation_wbtest.mbt`：固定种子 LCG 4 语料×300=1200 变异体；口径「要么 14 个声明变体之一要么放行」防假绿；sha256 单字符破坏必拒、版本首字符破坏必 None；双跑计数一致。
  - `tools/`：`parity.sh`（wasm/native 双目标摘要相等且 failed: 0）、`mutation-selfcheck.sh`（3 缺陷注入变红→还原复绿，trap 保证任何退出路径还原源码）、`ref-scan.sh`（悬空引用 / README 索引 / 14 变体簿记）、`cli-smoke.ps1`。均自包含，MOON 回退兼容 WSL interop。
- 测试增量：+12（7 性质 + 5 变异），总计 **110/110**。
- 实跑证据（Git Bash）：parity 双目标 110/110 OK；mutation-selfcheck 3/3 缺陷变红还原复绿；ref-scan 0 悬空 / 18 pub fn 索引齐 / 14/14 簿记。
- 裁决记录：无需（纯测试与工具加法）。

## 2026-11-16 · 终验汇总

- 五门禁全绿：`moon fmt`=0 / `moon info`=0 / `moon check --deny-warn`=0 / `moon build`=0 / `moon test` 110/110=0 / `moon fmt --check`=0。
- 计数演进：79 → 98（W2–W7 验收 +19）→ 110（W9 +12）。
- 快照审阅：`pkg.generated.mbti` +22 行纯加法（4 fn + 2 struct）；`cmd/main/pkg.generated.mbti` +1 行 `type Flags`；零删除零修改，API 冻结成立。
- 防火墙：旧 API 输出除两处裁决 golden 行外逐字节不变；旧用例零改动全绿。
- `git diff --stat`：15 个已跟踪文件 +941/-39；新增文件 7 个源码/文档 + 4 个 tools 脚本，自包含扫描零模块外引用。
- 未执行 git commit（等待用户明确指示）。