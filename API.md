# moon_android · 公开 API（API.md）

> 与 `pkg.generated.mbti` 一致。4 个函数全部为 `declare`（**无实现**，预期 4 × `0068` 告警）。
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

| 签名 | 参数与所有权 | 返回 / 错误 | 资源与线程约束 | TODO |
|---|---|---|---|---|
| `plan_build(config : BuildConfig, abis : Array[Abi]) -> BuildPlan raise MoonAndroidError` | `config` 只读；`abis` 为空时回落到 `config.abis` | 有序计划 / `InvalidPackage`、`UnsupportedAbi`、`ToolchainNotLocked`、`InvalidStepOrder`、`KeyMaterialEmbedded`、`SigningSchemeConflict`、`MissingTool` | **纯函数、确定性、可并发**；无句柄、无 I/O | 命令模板、双 ABI so 管理、Windows JDK 探测 |
| `render_script(plan : BuildPlan) -> String raise MoonAndroidError` | `plan` 只读 | 可审阅脚本文本（**仍不执行**） / `InvalidStepOrder`、`MissingTool` | 确定性输出，同输入两次逐字相等；不 spawn 进程 | aapt2/d8/zipalign/apksigner 命令模板 |
| `verify_artifact(plan : BuildPlan, artifact : Artifact) -> Bool raise MoonAndroidError` | 均为只读纯值 | `Bool` / `ArtifactMismatch` | 本库**不读文件、不算哈希**；`sha256` 由组合根填入后做值比对 | 签名块与 ABI 目录实测校验 |
| `ci_gate_plan() -> Array[Gate]` | 无参数 | 建议门禁序列（含 `CheckDenyWarn`） | 纯常量、可并发 | 与 `.github/workflows/ci.yml` 对齐（本轮不改 workflow） |

## 错误构造速查

`InvalidPackage(name)` · `UnsupportedAbi(name)` · `MissingTool(name)` · `ToolchainNotLocked(field)` · `InvalidStepOrder(first, second)` · `KeyMaterialEmbedded` · `SigningSchemeConflict(msg)` · `ArtifactMismatch(msg)` · `MissingGate(gate)`

## 安全与门禁提示

- `keystore_ref` 只存引用；`KeyMaterialEmbedded` 是显式拒绝信号，实现轮不得静默接受内嵌密钥。
- `ToolchainNotLocked`：任一版本字段为空即拒绝；本轮锁 `moon 0.1.20261102` / `moonc v0.10.19+bee578715`（ADR-0010）。
- `Gate::CheckDenyWarn` 在建议序列中，但**本轮按 ADR-0007 豁免执行**（65 条 `0068` 会被升级为 error），R4 实现补齐后再打开。

## Wire / 跨模块提示

`moon_abi` 只以**文本片段**形式与本库衔接，不传递 `LinkNativeConfig` 类型（K5）。`apk` 是逆向解析库，只产出 `ManifestRef.raw` / `DexEntry.bytes` 等 Blob，本库不 import `apk`，也不会解析 APK（ADR-0003 / 架构 §8）。

## 非目标

执行任何外部命令 · 签名与密钥管理 · adb 安装/启动 · 读写 APK · Gradle / IDE 集成 · 下载 SDK/NDK · 探测本机 JDK · 模板泛化（后移 R4）。

## 状态

`moon check`：✅ 0 error，4 × `0068`。`moon build`：可构建（无链接期阻塞，因无 FFI）。`moon test`：⚠️ 本轮无实际断言。API 快照：`pkg.generated.mbti`。实现：❌ 计划/配置部分 R1–R2，模板泛化 R4（ADR-0005 O6）。
