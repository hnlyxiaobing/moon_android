# moon_android · 公开 API（API.md）

> **API 冻结语义**：既有签名变更即破坏性变更；R4 全部改动为**加法性新增**（新类型 / 新函数 / 新错误构造），快照 `pkg.generated.mbti` 只增不删（`COMPATIBILITY.md` §10 三件套：快照审阅 + `API-CHANGELOG.md` 条目 + CI 第 5 道门禁；条目文本由主控登记）。
> **14 个公开函数**（4 既有 + 10 新增）均为**真实实现**（`pub fn`，非 `declare` 占位，0 条 `0068`）。
> `preferred_target = "wasm"`（未改动）。错误传播统一 `raise MoonAndroidError`。
> **纯 MoonBit 库**：无 `#external`、无 `extern "C"`、无回调、无 I/O、无脚本执行；JDK 探测为纯评估器（不读环境/注册表）。

## 类型（11 既有 + 13 新增 = 24 个值类型）

### 既有（R1，签名冻结）

| 类型 | 种类 | 说明 |
|---|---|---|
| `PackageId` | `pub(all) struct` | `{ name : String }`；字段名避开保留字 `package` |
| `ActivityKind` | `pub(all) enum` | `WebView` / `GlesSurface` / `NativeOnly` |
| `SigningScheme` | `pub(all) enum` | `V1` / `V2` / `V3` / `V31` |
| `BuildProfile` | `pub(all) enum` | `Debug` / `Release` |
| `Abi` | `pub(all) enum` | 4 种；与 `moon_abi::Abi` 同构但独立（组合根转换） |
| `ToolchainVersions` | `pub(all) struct` | 7 个必填字段 + `cmake : String?`；任一必填为空 = 未锁定 |
| `BuildConfig` | `pub(all) struct` | 包名 / Activity / entry_url / abis / min_sdk / target_sdk / 签名 / keystore_ref / profile / toolchain / extra_native_libs |
| `BuildStep` | `pub(all) enum` | 规范 10 步 |
| `BuildPlan` | `pub(all) struct` | `steps` / `inputs` / `outputs` / `config`；纯数据 |
| `Artifact` | `pub(all) struct` | `path` / `size_bytes` / `sha256` / `abis` / `signatures` |
| `Gate` | `pub(all) enum` | 7 项门禁，`#derive(Debug)` |
| `BuildPlanner` | `pub trait` | `fn plan(Self) -> BuildPlan raise MoonAndroidError` |

### 新增（R4，加法性）

| 类型 | 种类 | 说明 |
|---|---|---|
| `NativeLib` | `pub(all) struct` | `abi` / `dir`（必须 = ABI 目录名）/ `soname` / `sha256 : String?`（`None` = 未登记） |
| `LibHash` | `pub(all) struct` | `abi` / `sha256`；组合根构建后回填 |
| `AssetInjection` | `pub(all) struct` | `source` / `target`（`assets/` 下相对路径）/ `sha256`；资产内容不进入库 |
| `TemplateParams` | `pub(all) struct` | `config` / `app_name` / `module_deps`（文本契约）/ `assets` |
| `GeneratedKind` | `pub(all) enum` | `ManifestXml` / `StringsXml` / `NativeBuild` / `ModuleDeps` / `AbiManifest` / `AssetManifest` |
| `GeneratedFile` | `pub(all) struct` | `path`（相对模板根）/ `kind` / `content` |
| `GeneratedTree` | `pub(all) struct` | `root` / `app_name` / `files` / `native_libs` / `assets` / `build_plan` |
| `JdkSource` | `pub(all) enum` | `JavaHome` / `Registry` / `CommonPath` / `PathEntry` |
| `JdkEntry` | `pub(all) struct` | `path` / `version : String?` |
| `JdkCandidate` | `pub(all) struct` | `path`（归一化 `/`）/ `source` / `version` |
| `JdkProbeStatus` | `pub(all) enum` | `JdkFound` / `JdkNotFound` / `JdkVersionUnmatched` |
| `JdkProbeResult` | `pub(all) struct` | `status` / `selected : JdkCandidate?` / `candidates` / `diagnostics` |
| `JdkProbeEnv` | `pub(all) struct` | `java_home : JdkEntry?` / 注册表 / 常见路径 / PATH / `existing_jdk_dirs` / `required_major` |

**`BuildStep` 顺序约束**：`CrossCompile → Aapt2Compile → Aapt2Link → Javac → D8 → Assemble → Zipalign → Apksigner → Verify → AdbInstall`。`Zipalign` 必须早于 `Apksigner`，否则 `InvalidStepOrder`。

## 函数签名

### 既有 4 个（签名冻结）

| 签名 | 返回 / 错误 | 实现要点 |
|---|---|---|
| `plan_build(config : BuildConfig, abis : Array[Abi]) -> BuildPlan raise MoonAndroidError` | `InvalidPackage` / `ToolchainNotLocked` / `KeyMaterialEmbedded` / `SigningSchemeConflict` / `UnsupportedAbi` / `InvalidStepOrder` / `MissingTool` | 包名 → 版本锁 → 密钥 → 签名方案 → ABI → 步骤全序 → 工具可用 |
| `render_script(plan : BuildPlan) -> String raise MoonAndroidError` | `InvalidStepOrder` / `MissingTool` / `KeyMaterialEmbedded` | 确定性命令模板；**不执行** |
| `verify_artifact(plan : BuildPlan, artifact : Artifact) -> Bool raise MoonAndroidError` | `ArtifactMismatch` | 只做值规格与多重集合比对；不读文件、不算哈希 |
| `ci_gate_plan() -> Array[Gate]` | 无 | 固定 7 项门禁序列 |

### 新增 10 个（R4）

| 签名 | 返回 / 错误 | 实现要点 |
|---|---|---|
| `abi_dir_name(abi : Abi) -> String` | — | ABI → Android 目录名（`armeabi-v7a` / `arm64-v8a` / `x86` / `x86_64`） |
| `dual_abi_set() -> Array[Abi]` | — | R4 双 ABI 基线：`arm64-v8a` + `armeabi-v7a` |
| `parse_abi_dir_name(name : String) -> Abi raise MoonAndroidError` | `UnsupportedAbi(name)` | 目录名反解；大小写敏感、非法名拒绝 |
| `plan_native_libs(abis : Array[Abi], soname : String) -> Array[NativeLib] raise MoonAndroidError` | `UnsupportedAbi("none"/dir)` / `InvalidNativeLib` | 按输入顺序生成 `lib/<dir>/<soname>` 布局，`sha256 = None` |
| `attach_native_hashes(libs : Array[NativeLib], hashes : Array[LibHash]) -> Array[NativeLib] raise MoonAndroidError` | `MissingAbi(dir)` / `InvalidNativeLib` | 每个 ABI 恰一条哈希；重复/未知/非法哈希拒绝 |
| `validate_native_manifest(libs : Array[NativeLib], required : Array[Abi]) -> Unit raise MoonAndroidError` | `UnsupportedAbi` / `MissingAbi` / `InvalidNativeLib` | 结构 + 哈希已登记（fail-closed）+ required ABI 在场 |
| `render_native_manifest(libs : Array[NativeLib]) -> String raise MoonAndroidError` | `InvalidNativeLib` | 确定性清单 `lib/<dir>/<soname>  sha256=<hex>`；未登记即拒绝 |
| `plan_template(params : TemplateParams) -> GeneratedTree raise MoonAndroidError` | `plan_build` 全部错误 + `InvalidTemplate` / `InvalidAsset` / `InvalidNativeLib` | 6 个生成文件 + ABI 布局 + 10 步计划；纯函数 |
| `render_template_script(tree : GeneratedTree) -> String raise MoonAndroidError` | `KeyMaterialEmbedded` / `InvalidStepOrder` / `MissingTool` / `InvalidTemplate` / `InvalidAsset` / `InvalidNativeLib` | 四阶段脚本：物化目录树 / ABI 布局 / 资产 SHA-256 校验后复制 / `cd` 后执行构建计划；**不执行** |
| `probe_jdk(env : JdkProbeEnv) -> JdkProbeResult raise MoonAndroidError` | `InvalidJdkProbe` | 纯评估器：JAVA_HOME → 注册表 → 常见路径 → PATH；存在性 + 主版本匹配；零 I/O |

## 错误构造速查（14 个）

既有 9 个：`InvalidPackage(name)` · `UnsupportedAbi(name)` · `MissingTool(name)` · `ToolchainNotLocked(field)` · `InvalidStepOrder(first, second)` · `KeyMaterialEmbedded` · `SigningSchemeConflict(msg)` · `ArtifactMismatch(msg)` · `MissingGate(gate)`（`MissingGate` 仅白盒构造验证）。

新增 5 个：`MissingAbi(dir)`（required ABI 缺失 / 哈希缺失）· `InvalidNativeLib(msg)`（soname / 目录漂移 / 哈希格式 / 未登记清单渲染）· `InvalidAsset(msg)`（资产路径穿越 / 哈希非法 / target 重复）· `InvalidTemplate(msg)`（app_name / module_deps / 生成路径 / heredoc 分隔符注入）· `InvalidJdkProbe(msg)`（`required_major` 非法）。

## 安全与门禁提示

- `keystore_ref` 只存引用；`plan_build`、`render_script`、`plan_template`、`render_template_script` 均拒绝内嵌密钥（`KeyMaterialEmbedded`），不静默接受。
- `ToolchainNotLocked`：7 个必填版本字段任一为空即拒绝；夹具锁定 `moon 0.1.20261104` / `moonc v0.10.20+65efd5b93`（`DECISIONS.md` 决策 5）。
- 双 ABI fail-closed：`sha256 = None` 不等于通过；`render_native_manifest` 要求全部哈希已登记；`validate_native_manifest` 用 `dual_abi_set()` 作 `required` 时缺 32 位 `.so` 即 `MissingAbi("armeabi-v7a")`。
- 模板安全：`app_name` 非空 / 无控制字符 / ≤64；XML 5 特殊字符转义；资产与生成路径禁 `/` 开头、`..`、反斜杠、盘符、空段；heredoc 分隔符 `MOON_ANDROID_EOF_<i>` 内容整行命中即拒绝渲染（防脚本注入）。
- `Gate::CheckDenyWarn` 在建议序列中；实现完成后门禁统一含 `moon check --deny-warn`（0 条 `0068`）。

## Wire / 跨模块提示

`moon_abi` 只以**文本片段**衔接（`module_deps` 文本契约），不传递结构化类型（ADR-0002）。`apk` 是逆向解析库，本库不 import、不解析 APK。`TemplateParams.module_deps` 只是「组合根写目标 App `moon.pkg`」的输入清单，本库不写任何文件。

## 非目标

执行任何外部命令 · 签名与密钥管理 · adb 安装/启动 · 读写 APK · Gradle / IDE 集成 · 下载 SDK/NDK/JDK · 读取环境变量与注册表（JDK 采集器属组合根）· 嵌入资产/`.so` 内容 · 自动计算 SHA-256（组合根职责）。

## 状态

- **R4（2026-11-09）**：加法性新增 10 个 `pub fn` + 13 个公开类型 + 5 个错误构造；`pkg.generated.mbti` 经 `moon info` 再生成，diff 为纯加法（无既有签名修改/删除）。
- 五道门禁本机等价实跑全绿：`moon check --deny-warn`（0 warn / 0 error）· `moon build` · `moon test`（**79 passed / 0 failed**）· `moon fmt --check` · `moon info` + `git diff --exit-code -- pkg.generated.mbti cmd/main/pkg.generated.mbti`（exit 0）。
- 模板映射见 `TEMPLATE.md`；执行链风险与已知缺口见 `EXECUTION-CHAIN.md`；设计契约见 `DESIGN.md`。
