# moon_android · 设计契约（DESIGN.md）

> Round-1 起草 / 2026-11-06 ｜ **API 冻结前对账（R2 准备轮）/ 2026-11-07** ｜ 状态：**已实现**（计划 / 渲染 / 校验 / 门禁序列），无脚本执行、无打包逻辑（冻结后签名变更即破坏性变更）

## 1. 分层位置与职责

L4 工程交付层的**纯 MoonBit 计划/配置库**。职责：把「包名 + 入口 + ABI + 签名方案 + 工具链版本」编译成有序、可审阅、可校验的 `BuildPlan`，并定义 CI 门禁与产物验收规格。它是把 L1/L2/L3 的 MoonBit 产物变成「能在目标设备上运行」的**描述层**，不是执行层。

按 ADR-0005，本库的「计划/配置」部分在 W0（桌面可测），「一次性脚本泛化为模板」后移到 R4/W3 —— 先验证再抽象（详见 `README.md`「排序修正」）。

## 2. 模块边界 / 依赖方向 / 数据流

```
moon_abi::render ──(配置片段文本，非 import)──► 组合根写入未来 App 的 moon.pkg
                                                   │
BuildConfig + Abis                                  ▼
   └─► moon_android::plan_build ──► BuildPlan ──► render_script ──► 脚本文本（仅可审阅，不执行）
                                          │
                                          └─► verify_artifact(plan, Artifact) ──► Bool
```

- `moon_abi` 只输出配置文本、**不读打包产物**，避免 K5 环（`architecture.md` §2）。
- `apk` 是**逆向输入层**：只解析 APK 字节，不承担打包；签名在本库只是 `BuildStep::Apksigner` 计划项（§8 解耦自检）。
- 本库零 import、零 FFI、零外部句柄；脚本文本由组合根消费，本库不 spawn 进程。

## 3. 核心数据结构

| 类型 | 作用 |
|---|---|
| `PackageId { name }` | Android 包名包装（**字段名刻意避开保留字 `package`**，改为 `package_id`） |
| `ActivityKind` | `WebView` / `GlesSurface` / `NativeOnly` |
| `SigningScheme` | `V1` / `V2` / `V3` / `V31`（按 minSdk / targetSdk 决定） |
| `BuildProfile` | `Debug` / `Release` |
| `Abi` | 4 种（`moon_abi::Abi` 的**同构但独立**定义，组合根转换） |
| `ToolchainVersions` | `moon_cli` / `moonc` / `core` / `ndk` / `build_tools` / `platform` / `jdk` / `cmake?`；任一为空 = 未锁定 |
| `BuildConfig` | `package_id` / `activity` / `entry_url?` / `abis` / `min_sdk` / `target_sdk` / `signing_schemes` / `keystore_ref` / `profile` / `toolchain` / `extra_native_libs` |
| `BuildStep` | 有序 10 步：`CrossCompile` → `Aapt2Compile` → `Aapt2Link` → `Javac` → `D8` → `Assemble` → `Zipalign` → `Apksigner` → `Verify` → `AdbInstall` |
| `BuildPlan { steps, inputs, outputs, config }` | 纯数据，**不含可执行动作** |
| `Artifact` | `path` / `size_bytes` / `sha256` / `abis` / `signatures` |
| `Gate` | 7 项：`FmtCheck` / `Check` / `CheckDenyWarn` / `TestCoverage` / `Bench` / `InfoSnapshot` / `VersionLock` |
| `MoonAndroidError` | `pub suberror`，9 个可判定错误构造 |
| `BuildPlanner` trait | `fn plan(Self) -> BuildPlan raise MoonAndroidError`；确定性、可复现、无副作用 |

> 设计取舍：`BuildPlan` 是「步骤枚举 + 输入/输出名」而非命令字符串数组，本库**不泄漏**主机路径与环境探测结果；aapt2/d8/zipalign/apksigner 的**命令行模板由 `render_script` 产出可审阅文本**（仍不执行），参数细节不出现在上层类型里。这样换 build-tools 版本只改配置值，不改上层类型（`architecture.md` §7）。

## 4. 错误模型

`MoonAndroidError`：`InvalidPackage(String)`、`UnsupportedAbi(String)`、`MissingTool(String)`、`ToolchainNotLocked(String)`、`InvalidStepOrder(String, String)`、`KeyMaterialEmbedded`、`SigningSchemeConflict(String)`、`ArtifactMismatch(String)`、`MissingGate(Gate)`。

全部失败型 API 统一 `-> T raise MoonAndroidError`。其中 `KeyMaterialEmbedded` 与 `ToolchainNotLocked` 是**安全/合规的可观察信号**，`plan_build` 与 `render_script` 均主动返回而不是静默降级。`Gate` 已 `#derive(Debug)` + `pub extend Gate with Debug::{to_repr}`，以便放进错误构造时不产生 `E4018`。

## 5. 资源生命周期

**全部纯值**：无句柄、无 fd、无进程、无文件、无缓存。`plan_build` / `render_script` / `verify_artifact` 不修改输入，返回新值；无需释放函数。

`keystore_ref` **只存引用字符串**，绝不内嵌密钥材料（`KeyMaterialEmbedded`）。`Artifact` 中的 `sha256` 是元数据字段，本库不计算哈希、不读取文件——校验由组合根把外部计算结果填进来后做值比对。

## 6. 线程 / 并发边界

纯函数、确定性、无可变全局状态、无环境读取；可并发调用。本库**不引入**「探测本机 JDK / SDK 路径」这类隐式 I/O，否则确定性与 CI 快照测试都会失效。

## 7. 平台约束与外部依赖

- `preferred_target = "wasm"`（未改动），全后端；**产出的计划**面向 Android + 外部 SDK build-tools / NDK / JDK。
- 外部依赖：**无**（本轮）。`create-moonbit-raylib-android-app@0.1.0` 为 legacy 模板，只作参照不依赖（ADR-0010）。
- `[事实]` 无 android 编译目标；native 后端不能导出可链接 `.so/.dll`；因此 `CrossCompile` 步骤必须是「C stub + 宿主 NDK/CMake」。
- 许可：Android SDK License 3.4 禁止再分发 NDK/build-tools 二进制；**本库只分发计划与配置文本**。签名密钥不入库。
- `[待验证假设]` E3 / Q1：`mvp/android/build.ps1`、真实 APK、红米电视资产均不在本工作区，MVL-D「从 `moon build` 到应用启动一条命令」尚未复现。

## 8. 输入输出类型与错误传播（纯 MoonBit 库）

| 输入 | 输出 | 错误传播 |
|---|---|---|
| `BuildConfig + Array[Abi]` | `BuildPlan`（步骤顺序已校验） | `InvalidPackage` / `UnsupportedAbi` / `ToolchainNotLocked` / `InvalidStepOrder` / `KeyMaterialEmbedded` / `SigningSchemeConflict` / `MissingTool` |
| `BuildPlan` | `String`（脚本文本，确定性，仍不执行） | `InvalidStepOrder` / `MissingTool` |
| `BuildPlan + Artifact` | `Bool`（元数据是否一致） | `ArtifactMismatch` |
| 无 | `Array[Gate]`（建议门禁序列） | 无（纯常量） |

4 个函数均为 `pub fn` **真实实现**（无 `declare` 占位、无 `0068` 告警）；具体 `enum` / `struct` / `trait` / `suberror` 用真实类型定义（ADR-0001）。**无 `#external`、无 `extern "C"`、无回调、无所有权注解**。

## 9. 可替换性与实现细节不泄漏

上层只看到 `BuildPlan` / `ToolchainVersions` / `Artifact` / `Gate`；看不到 aapt2/d8 命令字符串、主机路径、JDK 探测、双 ABI so 布局、Activity XML 模板。换 build-tools / NDK 版本只改 `ToolchainVersions`；换壳 Activity 只改 `ActivityKind`；换签名方案只改 `Array[SigningScheme]`。若未来 MVL-D 证明通路由一次性脚本更合适，可直接把 `render_script` 的输出替换掉，不改上层调用（`README.md`「排序修正」）。

## 10. 测试策略

| 层次 | 内容 |
|---|---|
| 纯测 | 步骤顺序断言（`Zipalign` 早于 `Apksigner`）；`plan_build` 输出确定性双次比对；`abis` 为空时回落到 `config.abis` |
| 负例 | 版本锁缺失、非法包名、密钥内嵌、签名方案冲突、缺工具、产物元数据不符、缺门禁 |
| 快照 | `render_script` golden；`ci_gate_plan()` 序列快照（含 `CheckDenyWarn`） |
| 门禁 | 四道门禁：`moon check --deny-warn` / `moon build` / `moon test` / `moon fmt --check`（R2 准备轮实跑全绿，39 tests；11/11 模块拒警告通过） |
| 设备（后续轮） | MVL-D 一次性脚本 → 目标设备启动；R4 才做模板泛化与双 ABI |

> **门禁口径（R2 准备轮更新）**：R1 期因 65 条 `[0068] declaration_unimplemented` 曾按 ADR-0007 用普通 `moon check` 豁免 `--deny-warn`；实现完成后 `0068` 归零，**本轮起统一执行 `moon check --deny-warn`**，该豁免不再适用。

## 11. 验收标准（后续轮）

1. 纯测与快照全绿、计划确定性可证；2. MVL-D：从 `moon build` 到目标设备应用启动一条命令（依赖 E3 + Q1）；3. CI 四道门禁全绿（✅ R2 准备轮已含 `moon check --deny-warn`）；4. R4 模板泛化后外部开发者按文档可跑通。

## 12. 未解决问题 / 待验证假设

E3（P0）Android native 产物链路 · Q1（未解决）`mvp/` 与设备资产缺失 · Q7 legacy 模板迁移可编译性（仅参照）· aapt2/d8/zipalign/apksigner 命令模板已由 `render_script` 产出（可审阅、不执行），双 ABI so 管理与 Windows JDK 探测仍属组合根 / 后续轮 · 评审决策点 5（R1 期豁免 `--deny-warn`，R2 准备轮已恢复执行）、7（先一次性脚本、模板后移）。

## 13. 当前状态

`moon_android.mbt` 的 12 个值类型、`BuildPlanner` trait、`MoonAndroidError` 与 4 个 API（`plan_build` / `render_script` / `verify_artifact` / `ci_gate_plan`）均为**真实实现**，公开 API 带 `///` 文档注释；`pkg.generated.mbti` 快照与源码一致。**命令执行、签名、adb、APK 读写仍为非目标**（无脚本执行）。四道门禁全绿（39 tests，R2 准备轮实跑）。

## References

`../docs/architecture.md` §2 / §5.4 / §6 L4 / §7 / §8 · `../docs/dependency-graph.md` K5 / O3 / O6 · `../docs/adr/ADR-0005`、`ADR-0007`、`ADR-0010` · `../docs/roadmap-v2.md` 任务 AND-01 / MVL-D · `../docs/capability-matrix.md` 序 18 · `../docs/open-questions.md` E3 / Q1 / 决策点 5、7
