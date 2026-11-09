# moon_android · 设计契约（DESIGN.md）

> 初稿 2026-11-06 ｜ **API 冻结前对账 2026-11-07** ｜ 状态：**已实现**（计划 / 渲染 / 校验 / 门禁序列），无脚本执行、无打包逻辑（冻结后签名变更即破坏性变更）

## 1. 分层位置与职责

APK 打包链的**纯 MoonBit 计划/配置库**。职责：把「包名 + 入口 + ABI + 签名方案 + 工具链版本」编译成有序、可审阅、可校验的 `BuildPlan`，并定义 CI 门禁与产物验收规格。它是把 MoonBit 产物变成「能在目标设备上运行」的**描述层**，不是执行层。

按「先验证再抽象」的排序决策（`DECISIONS.md` 决策 2），本库的「计划/配置」部分先行（桌面可测），「一次性脚本泛化为模板」后移 —— 先用一次性脚本验证通路（详见 `README.md`「排序修正」）。

## 2. 模块边界 / 依赖方向 / 数据流

```
moon_abi::render ──(配置片段文本，非 import)──► 组合根写入未来 App 的 moon.pkg
                                                   │
BuildConfig + Abis                                  ▼
   └─► moon_android::plan_build ──► BuildPlan ──► render_script ──► 脚本文本（仅可审阅，不执行）
                                          │
                                          └─► verify_artifact(plan, Artifact) ──► Bool
```

- `moon_abi` 只输出配置文本、**不读打包产物**，与本库只以文本片段协作、不传递结构化类型，从结构上消解潜在循环依赖（`DECISIONS.md` 决策 3）。
- `apk` 是**逆向输入层**：只解析 APK 字节，不承担打包；签名在本库只是 `BuildStep::Apksigner` 计划项（`DECISIONS.md` 决策 4）。
- 本库零 import、零 FFI、零外部句柄；脚本文本由组合根消费，本库不 spawn 进程。

## 3. 核心数据结构

| 类型 | 作用 |
|---|---|
| `PackageId { name }` | Android 包名包装（**字段名刻意避开保留字 `package`**，改为 `package_id`） |
| `ActivityKind` | `WebView` / `GlesSurface` / `NativeOnly` |
| `SigningScheme` | `V1` / `V2` / `V3` / `V31`（按 minSdk / targetSdk 决定；`min_sdk < 24` 须 V1、V31 须与 V3 同启） |
| `BuildProfile` | `Debug` / `Release` |
| `Abi` | 4 种（`moon_abi::Abi` 的**同构但独立**定义，组合根转换） |
| `ToolchainVersions` | `moon_cli` / `moonc` / `core` / `ndk` / `build_tools` / `platform` / `jdk` 7 个必填字段 + 可选 `cmake`；任一必填字段为空 = 未锁定 |
| `BuildConfig` | `package_id` / `activity` / `entry_url?` / `abis` / `min_sdk` / `target_sdk` / `signing_schemes` / `keystore_ref` / `profile` / `toolchain` / `extra_native_libs` |
| `BuildStep` | 有序 10 步：`CrossCompile` → `Aapt2Compile` → `Aapt2Link` → `Javac` → `D8` → `Assemble` → `Zipalign` → `Apksigner` → `Verify` → `AdbInstall` |
| `BuildPlan { steps, inputs, outputs, config }` | 纯数据，**不含可执行动作** |
| `Artifact` | `path` / `size_bytes` / `sha256` / `abis` / `signatures` |
| `Gate` | 7 项：`FmtCheck` / `Check` / `CheckDenyWarn` / `TestCoverage` / `Bench` / `InfoSnapshot` / `VersionLock` |
| `MoonAndroidError` | `pub suberror`，9 个可判定错误构造 |
| `BuildPlanner` trait | `fn plan(Self) -> BuildPlan raise MoonAndroidError`；确定性、可复现、无副作用 |

> 设计取舍：`BuildPlan` 是「步骤枚举 + 输入/输出名」而非命令字符串数组，本库**不泄漏**主机路径与环境探测结果；aapt2/d8/zipalign/apksigner 的**命令行模板由 `render_script` 产出可审阅文本**（仍不执行），参数细节不出现在上层类型里。这样换 build-tools 版本只改配置值，不改上层类型。

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
- 外部依赖：**无**。`create-moonbit-raylib-android-app@0.1.0` 为 legacy 模板，只作参照不依赖（`DECISIONS.md` 决策 6）。
- `[事实]` 无 android 编译目标；native 后端不能导出可链接 `.so/.dll`；因此 `CrossCompile` 步骤必须是「C stub + 宿主 NDK/CMake」。
- 步骤顺序硬约束：`Zipalign` 必须先于 `Apksigner`（签名后任何改动都会使签名失效）。
- 签名方案约束：`min_sdk < 24` 必须启用 V1（低版本设备无法校验 v2+ 签名）；V31（密钥轮换）必须与 V3 同启；targetSdk 30+ 强制 v2+。
- 许可：Android SDK License 3.4 禁止再分发 NDK/build-tools 二进制；**本库只分发计划与配置文本**。签名密钥不入库。
- `[待验证假设]` 设备端通路：Android native 产物链路（MoonBit → C 源码/对象 → NDK clang + CMake 产出可加载 `.so`）未在本仓库复现；「从 `moon build` 到应用启动一条命令」的验收基线（一次性打包脚本、真实 APK、红米电视资产）均不在本仓库，设备端最小验证尚未复现。

## 8. 输入输出类型与错误传播（纯 MoonBit 库）

| 输入 | 输出 | 错误传播 |
|---|---|---|
| `BuildConfig + Array[Abi]` | `BuildPlan`（步骤顺序已校验） | `InvalidPackage` / `UnsupportedAbi` / `ToolchainNotLocked` / `InvalidStepOrder` / `KeyMaterialEmbedded` / `SigningSchemeConflict` / `MissingTool` |
| `BuildPlan` | `String`（脚本文本，确定性，仍不执行） | `InvalidStepOrder` / `MissingTool` |
| `BuildPlan + Artifact` | `Bool`（元数据是否一致） | `ArtifactMismatch` |
| 无 | `Array[Gate]`（建议门禁序列） | 无（纯常量） |

4 个函数均为 `pub fn` **真实实现**（无 `declare` 占位、无 `0068` 告警）；具体 `enum` / `struct` / `trait` / `suberror` 用真实类型定义（`declare` 不能声明具体类型，见 `DECISIONS.md`「声明策略」）。**无 `#external`、无 `extern "C"`、无回调、无所有权注解**。

## 9. 可替换性与实现细节不泄漏

上层只看到 `BuildPlan` / `ToolchainVersions` / `Artifact` / `Gate`；看不到 aapt2/d8 命令字符串、主机路径、JDK 探测、双 ABI so 布局、Activity XML 模板。换 build-tools / NDK 版本只改 `ToolchainVersions`；换壳 Activity 只改 `ActivityKind`；换签名方案只改 `Array[SigningScheme]`。若后续证明设备端通路由一次性脚本更合适，可直接把 `render_script` 的输出替换掉，不改上层调用（`README.md`「排序修正」）。

## 10. 测试策略

| 层次 | 内容 |
|---|---|
| 纯测 | 步骤顺序断言（`Zipalign` 早于 `Apksigner`）；`plan_build` 输出确定性双次比对；`abis` 为空时回落到 `config.abis` |
| 负例 | 版本锁缺失、非法包名、密钥内嵌、签名方案冲突、缺工具、产物元数据不符、缺门禁 |
| 快照 | `render_script` golden；`ci_gate_plan()` 序列快照（含 `CheckDenyWarn`） |
| 门禁 | 四道门禁：`moon check --deny-warn` / `moon build` / `moon test` / `moon fmt --check`（2026-11-07 实跑全绿，39 tests；同批 11 个模块拒警告通过） |
| 设备（后续阶段） | 一次性脚本 → 目标设备启动；模板泛化与双 ABI 在后续阶段 |

> **门禁口径（2026-11-07 更新）**：早期实现未完成阶段因 65 条 `[0068] declaration_unimplemented` 曾临时豁免 `--deny-warn`、用普通 `moon check` 作最低门槛；实现完成后 `0068` 归零，**统一执行 `moon check --deny-warn`**，该豁免不再适用（`DECISIONS.md` 决策 5）。

## 11. 验收标准（后续阶段）

1. 纯测与快照全绿、计划确定性可证；2. 设备端最小验证：从 `moon build` 到目标设备应用启动一条命令（依赖 §7 的待验证假设）；3. CI 四道门禁全绿（✅ 2026-11-07 已含 `moon check --deny-warn`）；4. 模板泛化后外部开发者按文档可跑通。

## 12. 未解决问题 / 待验证假设

- **Android native 产物链路**（最高优先级待验证假设）：MoonBit → C 源码/对象 → NDK clang + CMake 能否产出可加载 `.so`，本仓库无复现实验（见 §7）。
- **设备端最小验证资产缺失**：一次性打包脚本、真实 APK 与红米电视资产均不在本仓库，「一条命令到设备启动」尚未复现。
- legacy 模板迁移后的可编译性未验证（仅参照，不可依赖）。
- aapt2/d8/zipalign/apksigner 命令模板已由 `render_script` 产出（可审阅、不执行），双 ABI so 管理与 Windows JDK 探测仍属组合根 / 后续阶段。
- 门禁口径历史决策：`--deny-warn` 早期临时豁免、实现完成后恢复执行；排序历史决策：先一次性脚本、模板后移（详见 `DECISIONS.md`）。

## 13. 当前状态

`moon_android.mbt` 的 12 个值类型、`BuildPlanner` trait、`MoonAndroidError` 与 4 个 API（`plan_build` / `render_script` / `verify_artifact` / `ci_gate_plan`）均为**真实实现**，公开 API 带 `///` 文档注释；`pkg.generated.mbti` 快照与源码一致。**命令执行、签名、adb、APK 读写仍为非目标**（无脚本执行）。四道门禁全绿（39 tests，2026-11-07 实跑）。

## 参考

本仓库内文档：`README.md`（定位与排序修正）· `API.md`（公开接口）· `DECISIONS.md`（设计决策记录，含本文各项取舍的背景 / 决策 / 理由 / 后果）。
