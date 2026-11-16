# moon_android · Android 打包链计划层

> 独立发布单元 ｜ L4 工程交付 ｜ `preferred_target = wasm` ｜ Apache-2.0
> 状态：`moon test` **79/79** 通过（2026-11-11 本机实测）；本文件是本仓库**唯一**说明文档。
> 公开 API 以 `pkg.generated.mbti` 为准（由 `moon info` 生成，禁手工编辑）；加法性变更须登记簿记 + 快照审阅 + 快照门禁。

## 1. 定位与边界

把 Android 打包流程表达为可校验、可渲染、确定性的计划与脚本文本，供外部构建系统执行。

**能力**

- `plan_build` 十步顺序（`zipalign` 必须先于 `apksigner`，违规抛 `InvalidStepOrder`）
- `render_script` 输出带 `DO NOT EXECUTE` 头的脚本文本与生成目录树 `GeneratedTree`
- 密钥引用制（`keystore_ref`），四个入口拒绝 `KeyMaterialEmbedded`
- 模板泛化参数表、XML 五字符转义、`sha256sum -c` 校验、确定性输出
- `probe_jdk` 纯评估器；14 个公开函数 / 24 个值类型 / 14 个 `MoonAndroidError` 构造

**非目标**

- **不执行打包**：不调用 aapt2 / zipalign / apksigner，不产出可安装 APK
- 不内嵌密钥材料，不替调用方做版本决策

## 2. 关键设计决策（本仓库自足记录）

- 只做计划配置层，解析库不打包；先验证一次性脚本、再抽象为模板。
- G-1 缺陷已修复（2026-11-09）：`Assemble` 先把 `.so` stage 到 `lib/<abi>/` 再入包，两处 golden 书面重录；旧文档中「待维护者裁决」的表述已作废。
- 版本锁（build-tools 34.0.0 / android-34 / JDK 17）与 `--deny-warn` 门禁遵循工作区统一口径。
- `min_sdk < 24` 必须启用 v1 签名、V31 须启用 v3 签名。

## 3. 公开 API 索引（自动抽取 `pkg.generated.mbti` 的 `pub` 声明行；完整字段见快照）

```text
pub fn abi_dir_name(Abi) -> String
pub fn attach_native_hashes(Array[NativeLib], Array[LibHash]) -> Array[NativeLib] raise MoonAndroidError
pub fn ci_gate_plan() -> Array[Gate]
pub fn dual_abi_set() -> Array[Abi]
pub fn parse_abi_dir_name(String) -> Abi raise MoonAndroidError
pub fn plan_build(BuildConfig, Array[Abi]) -> BuildPlan raise MoonAndroidError
pub fn plan_native_libs(Array[Abi], String) -> Array[NativeLib] raise MoonAndroidError
pub fn plan_template(TemplateParams) -> GeneratedTree raise MoonAndroidError
pub fn probe_jdk(JdkProbeEnv) -> JdkProbeResult raise MoonAndroidError
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
pub(all) enum SigningScheme {
pub(all) struct TemplateParams {
pub(all) struct ToolchainVersions {
```

## 4. 依赖、平台与许可

零第三方依赖（仅 core/test）；`preferred_target = wasm`；Apache-2.0。

## 5. 命令行与验证

- `cmd/main` 仍是模板 `Hello`（无实际 CLI）；本库以 API 与渲染文本对外。
- 复验：`moon clean` → `moon check --deny-warn` → `moon build` → `moon test` → `moon fmt --check` → `moon info` 后检查 `pkg.generated.mbti` 无意外 diff。
- 本仓库为独立 Git 仓库，文档与 CI 均自包含，不依赖工作区其他目录。

## 6. 风险与未决

- 未产出可执行打包链，交付通路 A4 仍依赖 E3 复现。
- 本机 build-tools 35.0.0 与锁值 34.0.0 的差距须在真机轮统一。

