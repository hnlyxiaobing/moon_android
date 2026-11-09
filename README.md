# hnlyxiaobing/moon_android

**MoonBit → Android 打包链的「计划与配置」契约 —— 构建计划、工具链版本锁、CI 门禁序列与产物校验规格。**

> 状态：**实现完成，API 冻结前对账（2026-11-07）**。12 个值类型、`BuildPlanner` trait、`MoonAndroidError` 与 4 个 API（`plan_build` / `render_script` / `verify_artifact` / `ci_gate_plan`）全部为真实实现（0 条 `0068`），四道门禁 `moon check --deny-warn` / `moon build` / `moon test` / `moon fmt --check` 全绿（39 tests；`pkg.generated.mbti` 与源码对账一致，冻结后签名变更即破坏性变更）。**无脚本执行、无签名、无 adb、无 APK 读写**。
> `preferred_target = "wasm"`（骨架原值，未改动）；全后端、桌面可测。
> **与骨架 README / 报告定位差异**：骨架把本项目定为 **「先解决能出包」的起点**；本仓库按「先验证再抽象」的排序决策（见 `DECISIONS.md` 决策 2）把「一次性脚本泛化为可配置模板」**后移**，先用一次性脚本验证通路。原因与影响见下文「排序修正」。

## 排序修正（重要，完整理由见 `DECISIONS.md` 决策 2）

| 项 | 原报告 / 骨架 README | 本仓库路线 | 原因 |
|---|---|---|---|
| 优先级 | 「先解决能出包」的里程碑起点 | 计划/配置部分先行（桌面可测）；**模板泛化后移** | 「先验证再抽象」：在通路上板前泛化模板，会把未验证的假设固化成接口，返工成本高 |
| 首轮交付 | 泛化脚本 `moon android build --abi …` | **一次性 shell APK 脚本**（设备端最小验证基线，本仓库不实现，仅作验收基线） | 更小替代方案；一次性脚本足以证明「MoonBit 产物能在目标设备启动」 |
| 依赖 | 被推理 / 插桩任务硬依赖（NDK 交叉编译） | NDK 交叉编译**降级为上板软依赖** | C API `.so` 与插桩 devkit 都是预编译产物，桌面验证不需要 NDK |
| 影响 | 打包链阻塞其他任务 | FFI 模块可与打包链并行推进 | 上板时仍必须补 `moon_abi` 配置，**不能省略** |

**被替代方案**：直接做参数化模板 + WebView/GLES 双壳 Activity + 双 ABI so 管理。风险：若 Android native 产物链路（MoonBit → C 源码/对象 → NDK clang + CMake 产出可加载 `.so`）未跑通，模板全部作废；且作为验收基线的一次性打包脚本、真实 APK 与目标设备资产**均不在本仓库**，设备端最小验证目前无法在本仓库内复现（见「风险与待验证」）。

## 定位与为什么存在

`moon build --target` 只有 wasm / wasm-gc / js / native / llvm / all，**没有 android 目标**；官方「一门语言、多后端」未把 Android 集成列入目标；社区只有 JNI 桥接件，没有「一条命令出 APK」。可行路径是「C stub + 宿主 NDK/CMake + aapt2 / d8 / zipalign / apksigner」外围工具链。

**选「纯 MoonBit 自研（计划 + 配置）」**（选型判定见 `DECISIONS.md` 决策 6）：`create-moonbit-raylib-android-app@0.1.0` 是 legacy 模板（仍带 `moon.pkg.json`），只能作参照、不可直接依赖；本仓库零新增依赖。

## 能力范围 / 非目标

- **做**：由 `BuildConfig` 生成有序 `BuildPlan`（含步骤顺序校验）、渲染可审阅的脚本文本、校验产物元数据（size / sha256 / ABI / 签名方案）、给出建议的 CI 门禁序列。
- **不做**：**不执行任何外部命令**、不签名、不调 adb、不读写 APK、不实现 Gradle / IDE 集成、不管理密钥材料、不探测 JDK、不下载 SDK。
- 步骤顺序硬约束：`BuildStep::Zipalign` 必须在 `BuildStep::Apksigner` 之前（签名后任何改动都会使签名失效）；`InvalidStepOrder` 用于拒绝违规计划。
- 「解析库不承担打包」：`apk` 无任何签名/打包 API；签名只作为 `BuildStep::Apksigner` 计划项出现在本库，且不执行（`DECISIONS.md` 决策 4）。
- 与 `moon_abi` 是**数据契约（配置片段文本），不是 import**，名义类型隔离、消解潜在循环依赖（`DECISIONS.md` 决策 3）。

## 公开接口（速览）

`plan_build(config, abis)` · `render_script(plan)` · `verify_artifact(plan, artifact)` · `ci_gate_plan()`。完整签名见 `API.md`。

## 依赖

- **零依赖**：无 `moon add`、未改 `moon.pkg`、无 FFI、无外部句柄。
- 后续（脚本**执行**，属组合根）：Android SDK build-tools（aapt2 / d8 / zipalign / apksigner）、NDK、JDK、adb——本库只输出命令模板文本，不执行。**SDK/NDK 二进制不可再分发**（Android SDK License 3.4），本库只分发计划与配置文本。
- `keystore_ref : String` 只存**引用**，禁止内嵌密钥材料（`MoonAndroidError::KeyMaterialEmbedded` 是可观察的拒绝信号）。

## 平台与许可风险

| 风险 | 说明 |
|---|---|
| 工具链无 Android 目标 | 必须走「C stub + 宿主 NDK/CMake」；`foreign_library` 不能导出可链接 `.so/.dll`（`[事实]`） |
| 版本未锁 | `ToolchainVersions` 7 个必填字段任一为空视为未锁定，CI 必须拒绝（`ToolchainNotLocked`）；当前 pin `moon 0.1.20261104` / `moonc v0.10.20+65efd5b93`（`DECISIONS.md` 决策 5） |
| 密钥 | 签名密钥不入库；`KeyMaterialEmbedded` 显式拒绝 |
| 门禁 | `Gate::CheckDenyWarn` 已列入建议序列；早期实现未完成阶段曾临时豁免（`0068` 会升级为 error），**实现完成、`0068` 归零后豁免失效，四道门禁统一含 `moon check --deny-warn`（同批 11 个模块拒警告通过）** |
| 主机差异 | Windows JDK 探测、32/64 位双 ABI so 管理属组合根 / 后续阶段（本库不探测 JDK，`ToolchainNotLocked` 只校验锁定值） |
| 许可 | SDK/NDK 构件不可再分发；`create-...-app` legacy 模板只作参照 |

## 测试与验收

- **纯测（桌面 CI 可跑）**：步骤顺序断言（zipalign 早于 apksigner）；版本锁缺失 → `ToolchainNotLocked`；包名非法 → `InvalidPackage`；密钥内嵌 → `KeyMaterialEmbedded`；签名方案冲突（`min_sdk < 24` 缺 V1、V31 缺 V3 等）→ `SigningSchemeConflict`；`render_script` 确定性双次比对；`verify_artifact` 元数据不符 → `ArtifactMismatch`。
- **验收标准**：从 `moon build` 到目标设备（红米电视 Android 9 / armeabi-v7a / 2GB）应用启动一条命令（依赖下文「风险与待验证」两项，未复现）；CI 四道门禁全绿（✅ 2026-11-07 实跑：`moon check --deny-warn` / `moon build` / `moon test` / `moon fmt --check`，39 tests）。
- **门禁实跑（2026-11-07）**：`moon clean` → `moon check --deny-warn` → `moon build` → `moon test`（**39 tests** 全过）→ `moon fmt --check`，全部 exit 0；无链接期阻塞（无 FFI）。设备端最小验证仍依赖下述资产定位与实验结论。

## 风险与待验证

- **Android native 产物链路（最高优先级待验证假设）**：「MoonBit → C 源码/对象 → NDK clang + CMake」能否产出可加载 `.so`（native `foreign_library` 不能导出 `.so`）——这是设备端交付通路的前提，开发期报告称手工跑通但**本仓库无复现证据**。最小实验：最小 MoonBit 模块 + 一个 C stub，NDK clang 编出 `.so`，塞进 shell APK，在设备上加载并打印。
- **设备端最小验证资产缺失**：「从 `moon build` 到应用启动一条命令」的验收基线依赖一次性打包脚本、真实 APK 与目标设备（红米电视）资产，**均不在本仓库**，当前无法在本仓库内复现。
- legacy 模板迁移后的可编译性未验证（`create-moonbit-raylib-android-app` 仅作参照）。

## 当前状态 / 本仓库产物

| 项 | 状态 |
|---|---|
| `moon_android.mbt`：值类型 ×12、`BuildPlanner` trait、`MoonAndroidError`（9 构造）、API ×4（真实实现） | ✅ |
| `pkg.generated.mbti` API 快照（与源码对账一致） | ✅ |
| 命令模板（`render_script` 产出可审阅文本）/ 脚本执行 / 签名 / adb / 双 ABI 模板泛化 | 命令模板 ✅；执行、签名、adb、模板泛化 ❌ 非目标或后续阶段 |
| 四道门禁：`moon check --deny-warn` / `moon build` / `moon test` / `moon fmt --check` | ✅ 全绿（39 tests） |

## 文档索引

`DESIGN.md`（设计契约）· `API.md`（公开接口）· `DECISIONS.md`（设计决策记录：定位 / 排序 / 文本契约 / 解析不打包 / 版本锁与门禁 / 依赖政策 / 声明策略）
