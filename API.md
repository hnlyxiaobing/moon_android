# moon_android · 公开 API（API.md）

> **API 冻结前对账（R2 准备轮，2026-11-07）**：本文已与 `pkg.generated.mbti` 快照及源码公开签名逐项对账一致；**冻结后签名变更即破坏性变更**。
> 4 个函数均为**真实实现**（`pub fn`，非 `declare` 占位，0 条 `0068`）。
> `preferred_target = "wasm"`（未改动）。错误传播统一 `raise MoonAndroidError`。
> **纯 MoonBit 库**：无 `#external`、无 `extern "C"`、无回调、无 I/O、无脚本执行。

## 类型

| 类型 | 种类 | 说明 |
|---|---|---|
| `PackageId` | `pub(all) struct` | `{ name : String }`；字段名避开保留字 `package` |
| `ActivityKind` | `pub(all) enum` | `WebView` / `GlesSurface` / `NativeOnly` |
| `SigningScheme` | `pub(all) enum` | `V1` / `V2` / `V3` / `V31` |
| `BuildProfile` | `pub(all) enum` | `Debug` / `Release` |
| `Abi` | `pub(all) enum` | 4 种；与 `moon_abi::Abi` 同构但独立（组合根转换） |
| `ToolchainVersions` | `pub(all) struct` | `moon_cli` / `moonc` / `core` / `ndk` / `build_tools` / `platform` / `jdk` / `cmake : String?`；任一为空 = 未锁定 |
| `BuildConfig` | `pub(all) struct` | `package_id` / `activity` / `entry_url : String?` / `abis` / `min_sdk` / `target_sdk` / `signing_schemes` / `keystore_ref` / `profile` / `toolchain` / `extra_native_libs` |
| `BuildStep` | `pub(all) enum` | 有序 10 步，见下 |
| `BuildPlan` | `pub(all) struct` | `steps` / `inputs` / `outputs` / `config`；**纯数据，不含可执行动作** |
| `Artifact` | `pub(all) struct` | `path` / `size_bytes : UInt64` / `sha256` / `abis` / `signatures` |
| `Gate` | `pub(all) enum` | 7 项门禁，`#derive(Debug)` |
| `MoonAndroidError` | `pub suberror` | 9 个错误构造 |
| `BuildPlanner` | `pub trait` | `fn plan(Self) -> BuildPlan raise MoonAndroidError`（确定性、无副作用） |

**`BuildStep` 顺序约束**：`CrossCompile → Aapt2Compile → Aapt2Link → Javac → D8 → Assemble → Zipalign → Apksigner → Verify → AdbInstall`。`Zipalign` 必须早于 `Apksigner`，否则 `InvalidStepOrder`。

## 函数签名

| 签名 | 参数与所有权 | 返回 / 错误 | 资源与线程约束 | 实现要点 / 备注 |
|---|---|---|---|---|
| `plan_build(config : BuildConfig, abis : Array[Abi]) -> BuildPlan raise MoonAndroidError` | `config` 只读；`abis` 为空时回落到 `config.abis` | 有序计划 / `InvalidPackage`、`ToolchainNotLocked`、`KeyMaterialEmbedded`、`SigningSchemeConflict`、`UnsupportedAbi`、`InvalidStepOrder`、`MissingTool`（按源码校验次序） | **纯函数、确定性、可并发**；无句柄、无 I/O | **已实现**：包名 → 版本锁 → 密钥内嵌 → 签名方案 → ABI 集 → 步骤全序 → 工具可用的逐级校验；双 ABI so 管理与 Windows JDK 探测仍属组合根 / 后续轮 |
| `render_script(plan : BuildPlan) -> String raise MoonAndroidError` | `plan` 只读 | 可审阅脚本文本（**仍不执行**） / `InvalidStepOrder`、`MissingTool`、`KeyMaterialEmbedded` | 确定性输出，同输入两次逐字相等；不 spawn 进程 | **已实现**：aapt2 / d8 / zipalign / apksigner 命令行模板与每步工具清单；`keystore_ref` 内嵌密钥时拒绝渲染 |
| `verify_artifact(plan : BuildPlan, artifact : Artifact) -> Bool raise MoonAndroidError` | 均为只读纯值 | `Bool` / `ArtifactMismatch` | 本库**不读文件、不算哈希**；`sha256` 由组合根填入后做值比对 | **已实现**：产物路径、非空、64 位十六进制 `sha256`、ABI 与签名方案多重集合比对 |
| `ci_gate_plan() -> Array[Gate]` | 无参数 | 建议门禁序列（含 `CheckDenyWarn`） | 纯常量、可并发 | 固定顺序 `FmtCheck → Check → CheckDenyWarn → TestCoverage → Bench → InfoSnapshot → VersionLock`；CI workflow 文件属根目录 `.github/`（不在本模块范围），四道门禁口径见「状态」 |

## 错误构造速查

`InvalidPackage(name)` · `UnsupportedAbi(name)` · `MissingTool(name)` · `ToolchainNotLocked(field)` · `InvalidStepOrder(first, second)` · `KeyMaterialEmbedded` · `SigningSchemeConflict(msg)` · `ArtifactMismatch(msg)` · `MissingGate(gate)`（`MissingGate` 参与错误模型完整性，仅由白盒测试构造验证；4 个公开函数当前不抛出它）

## 安全与门禁提示

- `keystore_ref` 只存引用；`KeyMaterialEmbedded` 是显式拒绝信号，`plan_build` 与 `render_script` 均会主动返回，**不静默接受内嵌密钥**。
- `ToolchainNotLocked`：任一版本字段为空即拒绝；测试夹具与快照锁定 `moon 0.1.20261102` / `moonc v0.10.19+bee578715`（ADR-0010）。
- `Gate::CheckDenyWarn` 在建议序列中；**R2 准备轮起四道门禁含 `moon check --deny-warn`，11/11 模块拒警告通过（0 条 `0068`）**，ADR-0007 的 R1 期豁免已随实现完成而失效。

## Wire / 跨模块提示

`moon_abi` 只以**文本片段**形式与本库衔接，不传递 `LinkNativeConfig` 类型（K5）。`apk` 是逆向解析库，只产出 `ManifestRef.raw` / `DexEntry.bytes` 等 Blob，本库不 import `apk`，也不会解析 APK（ADR-0003 / 架构 §8）。

## 非目标

执行任何外部命令 · 签名与密钥管理 · adb 安装/启动 · 读写 APK · Gradle / IDE 集成 · 下载 SDK/NDK · 探测本机 JDK · 模板泛化（后移 R4）。

## 状态

**API 冻结前对账（R2 准备轮）**：API.md ↔ `pkg.generated.mbti` ↔ 源码公开签名三方一致；**冻结后签名变更即破坏性变更**。
四道门禁实跑全绿（2026-11-07）：`moon check --deny-warn`（0 error / 0 warn）· `moon build` · `moon test`（**39 tests** 全过）· `moon fmt --check`。
API 快照：`pkg.generated.mbti`（只读，未改动）。实现：✅ 计划 / 渲染 / 校验 / 门禁序列均已完成；**命令执行、签名、adb、APK 读写仍为非目标**，模板泛化属 R4（ADR-0005 O6）。
