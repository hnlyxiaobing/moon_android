# moon_android · Android 打包链计划层

> 独立发布单元 ｜ L4 工程交付 ｜ `preferred_target = wasm` ｜ Apache-2.0
> 状态：`moon test` **110/110** 通过（2026-11-16 本机实测，wasm 与 native 双目标 parity）；本文件是本仓库唯一**说明**文档（docs/ 存放带日期的开发/测试设计文档与 CHANGELOG）。
> 公开 API 以 `pkg.generated.mbti` 为准（由 `moon info` 生成，禁手工编辑）；加法性变更须登记簿记 + 快照审阅 + 快照门禁。

## 1. 定位与边界

把 Android 打包流程表达为可校验、可渲染、确定性的计划与脚本文本，供外部构建系统执行。

**能力**

- `plan_build` 恒产出规范十步顺序；步骤全序约束（`zipalign` 必须先于 `apksigner`）在渲染入口对任意计划强制，违规抛 `InvalidStepOrder`
- `render_script` / `render_template_script` 输出带 `DO NOT EXECUTE` 头 + `set -eu`（fail-closed）的脚本文本与生成目录树 `GeneratedTree`
- 密钥引用制（`keystore_ref`），四个入口拒绝 `KeyMaterialEmbedded`
- 模板泛化参数表、XML 五字符转义、`sha256sum -c` 校验、确定性输出
- `verify_artifact`：path/ABI/签名多重集合与计划比对；size/sha256 仅规格检查（非零 / 64 位十六进制），计划无期望值可比
- `check_sdk_range` / `check_entry_url` 值化校验报告（零 raise；调用方据报告自行拒绝，不改 `plan_build` 放行行为）
- `plan_extra_native_libs`：`extra_native_libs` 由组合根经本函数消费，`plan_build` 不自动入包
- `probe_jdk` 纯评估器（version=None fail-open 为明示设计）；`probe_jdk_strict` 为 fail-closed 替代入口
- 18 个公开函数 / 26 个值类型 / 14 个 `MoonAndroidError` 构造

**非目标**

- **不执行打包**：不调用 aapt2 / zipalign / apksigner，不产出可安装 APK
- 不内嵌密钥材料，不替调用方做版本决策

## 2. 关键设计决策（本仓库自足记录）

- 只做计划配置层，解析库不打包；先验证一次性脚本、再抽象为模板。
- G-1 缺陷已修复（2026-11-09）：`Assemble` 先把 `.so` stage 到 `lib/<abi>/` 再入包，两处 golden 书面重录；旧文档中「待维护者裁决」的表述已作废。
- 版本锁（build-tools 34.0.0 / android-34 / JDK 17）与 `--deny-warn` 门禁遵循工作区统一口径。
- `min_sdk < 24` 必须启用 v1 签名、V31 须启用 v3 签名。
- `MissingGate` 为保留错误变体（当前库内无触发点，不删不强行接线）；`ci_gate_plan()` 仅为建议序列，不代表 CI 实况。
- 渲染脚本头部 `set -eu`（W2，2026-11-16 裁决）：任一命令失败即终止，资产哈希校验失败后不再复制；两处 golden 书面重录。
- apksigner 命令只用官方 flag（W3，2026-11-16 裁决）：无 `--v31-signing-enabled`（官方不存在）；V31 渲染为轮换语义注释 + v3 flag，并显式传 `--min-sdk-version` / `--max-sdk-version`。
- `jdk_major` 每段数字限 9 位（W6）：防 Int32 回绕伪匹配，超限 fail-closed 返回 None。

## 3. 公开 API 索引（自动抽取 `pkg.generated.mbti` 的 `pub` 声明行；完整字段见快照）

```text
pub fn abi_dir_name(Abi) -> String
pub fn attach_native_hashes(Array[NativeLib], Array[LibHash]) -> Array[NativeLib] raise MoonAndroidError
pub fn check_entry_url(BuildConfig) -> EntryUrlReport
pub fn check_sdk_range(BuildConfig) -> SdkRangeReport
pub fn ci_gate_plan() -> Array[Gate]
pub fn dual_abi_set() -> Array[Abi]
pub fn parse_abi_dir_name(String) -> Abi raise MoonAndroidError
pub fn plan_build(BuildConfig, Array[Abi]) -> BuildPlan raise MoonAndroidError
pub fn plan_extra_native_libs(Array[String], Array[Abi]) -> Array[NativeLib] raise MoonAndroidError
pub fn plan_native_libs(Array[Abi], String) -> Array[NativeLib] raise MoonAndroidError
pub fn plan_template(TemplateParams) -> GeneratedTree raise MoonAndroidError
pub fn probe_jdk(JdkProbeEnv) -> JdkProbeResult raise MoonAndroidError
pub fn probe_jdk_strict(JdkProbeEnv) -> JdkProbeResult raise MoonAndroidError
pub fn render_native_manifest(Array[NativeLib]) -> String raise MoonAndroidError
pub fn render_script(BuildPlan) -> String raise MoonAndroidError
pub fn render_template_script(GeneratedTree) -> String raise MoonAndroidError
pub fn validate_native_manifest(Array[NativeLib], Array[Abi]) -> Unit raise MoonAndroidError
pub fn verify_artifact(BuildPlan, Artifact) -> Bool raise MoonAndroidError
pub(all) enum Abi {
pub(all) enum ActivityKind {
pub(all) struct Artifact {
pub(all) struct AssetInjection {
pub(all) struct BuildConfig {
pub(all) struct BuildPlan {
pub(all) enum BuildProfile {
pub(all) enum BuildStep {
pub(all) struct EntryUrlReport {
pub(all) enum Gate {
pub(all) struct GeneratedFile {
pub(all) enum GeneratedKind {
pub(all) struct GeneratedTree {
pub(all) struct JdkCandidate {
pub(all) struct JdkEntry {
pub(all) struct JdkProbeEnv {
pub(all) struct JdkProbeResult {
pub(all) enum JdkProbeStatus {
pub(all) enum JdkSource {
pub(all) struct LibHash {
pub(all) struct NativeLib {
pub(all) struct PackageId {
pub(all) struct SdkRangeReport {
pub(all) enum SigningScheme {
pub(all) struct TemplateParams {
pub(all) struct ToolchainVersions {
```

```text
pub trait BuildPlanner {
  fn plan(Self) -> BuildPlan raise MoonAndroidError
}
```

## 4. 依赖、平台与许可

零第三方依赖（仅 core/test）；`preferred_target = wasm`；Apache-2.0。

## 5. 命令行与验证

- `cmd/main` 为薄 CLI（W8，2026-11-16 裁决采纳 A 案）：子命令 `gates` / `render` / `template` / `probe-jdk`；退出码 **0=成功 / 1=校验失败（stderr 打印库错误变体名）/ 2=用法错误**；stdout 只输出渲染文本/门禁清单/探测报告，永不输出密钥材料。不执行打包、不读密钥文件。
  - 示例：`moon run cmd/main -- render --package com.example.app --abis arm64-v8a --min-sdk 24 --target-sdk 34 --schemes V2,V3 --keystore-ref @keys/release.jks`
  - 退出码矩阵本地实跑：`tools/cli-smoke.ps1`（Windows）。
- 门禁脚本（bash，自包含）：`tools/parity.sh`（wasm/native 双目标计数一致）、`tools/mutation-selfcheck.sh`（3 类缺陷注入必须变红后还原复绿）、`tools/ref-scan.sh`（悬空引用 + README 索引 + 错误簿记 14/14）。
- 复验：`moon clean` → `moon check --deny-warn` → `moon build` → `moon test` → `moon fmt --check` → `moon info` 后检查 `pkg.generated.mbti` 无意外 diff。
- 本仓库为独立 Git 仓库，文档与 CI 均自包含，不依赖工作区其他目录。

## 6. 风险与未决

- 未产出可执行打包链，交付通路 A4 仍依赖 E3 复现。
- 本机 build-tools 35.0.0 与锁值 34.0.0 的差距须在真机轮统一。

