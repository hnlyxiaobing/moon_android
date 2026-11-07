# hnlyxiaobing/moon_android

**MoonBit → Android 打包链的「计划与配置」契约 —— 构建计划、工具链版本锁、CI 门禁序列与产物校验规格。**

> 状态：**实现完成，API 冻结前对账（R2 准备轮）**。12 个值类型、`BuildPlanner` trait、`MoonAndroidError` 与 4 个 API（`plan_build` / `render_script` / `verify_artifact` / `ci_gate_plan`）全部为真实实现（0 条 `0068`），四道门禁 `moon check --deny-warn` / `moon build` / `moon test` / `moon fmt --check` 全绿（39 tests；`pkg.generated.mbti` 与源码对账一致，冻结后签名变更即破坏性变更）。**无脚本执行、无签名、无 adb、无 APK 读写**。
> `preferred_target = "wasm"`（骨架原值，未改动）；全后端、桌面可测。
> **与原 README / 报告定位差异**：骨架把本项目定为 **P0「先解决能出包」、M0 起点**；本轮按 ADR-0005 把「一次性脚本泛化为可配置模板」后移到 **R4 / W3**，先用 MVL-D 一次性脚本验证通路。原因与影响见下文「排序修正」。

## 排序修正（重要，对应 ADR-0005 / O6）

| 项 | 原报告 / 骨架 README | 本轮路线图 | 原因 |
|---|---|---|---|
| 优先级 | P0，M0 里程碑起点 | 计划/配置部分 W0；**模板泛化 R4 / W3** | 「先验证再抽象」：在通路上板前泛化模板，会把未验证的假设固化成接口，返工成本高 |
| 首轮交付 | 泛化脚本 `moon android build --abi …` | **MVL-D 一次性 shell APK 脚本**（本轮不实现，仅作为验收基线） | 更小替代方案；一次性脚本足以证明「MoonBit 产物能在目标设备启动」 |
| 依赖 | 被 `TFL-01` / `FRD-01` 硬依赖（NDK 交叉编译） | NDK 交叉编译**降级为上板软依赖** | C API `.so` 与 gum devkit 都是预编译产物，桌面验证不需要 NDK（O3） |
| 影响 | 解除 W1 对 W0 打包链的阻塞 | FFI 模块可与打包链并行推进 | 上板时仍必须补 `moon_abi` 配置，**不能省略** |

**被替代方案**：直接在 M0 做参数化模板 + WebView/GLES 双 Activity + 双 ABI so 管理。风险：若 E3（Android native 产物链路）未跑通，模板全部作废；且 Q1 显示 `mvp/android/build.ps1`、`docs/feasibility-redmi-tv.md`、真实 APK 与红米电视资产**均不在本工作区**，MVL-D 目前无法复现。

## 定位与为什么存在

路线图「拼图四」复核（2026-11-06）：`moon build --target` 只有 wasm / wasm-gc / js / native / llvm / all，**没有 android 目标**；官方「一门语言、多后端」未把 Android 集成列入目标；社区只有桥接件 `ajni`，没有「一条命令出 APK」。可行路径是「C stub + 宿主 NDK/CMake + aapt2 / d8 / zipalign / apksigner」外围工具链。

**选「纯 MoonBit 自研（计划 + 配置）」**（`capability-matrix.md` 序 18）：`create-moonbit-raylib-android-app@0.1.0` 是 legacy 模板（仍带 `moon.pkg.json`），只能作参照、不可直接依赖；本轮零新增依赖（ADR-0010）。

## 能力范围 / 非目标

- **做**：由 `BuildConfig` 生成有序 `BuildPlan`（含步骤顺序校验）、渲染可审阅的脚本文本、校验产物元数据（size / sha256 / ABI / 签名方案）、给出建议的 CI 门禁序列。
- **不做**：**不执行任何外部命令**、不签名、不调 adb、不读写 APK、不实现 Gradle / IDE 集成、不管理密钥材料、不探测 JDK、不下载 SDK。
- 步骤顺序硬约束：`BuildStep::Zipalign` 必须在 `BuildStep::Apksigner` 之前；`InvalidStepOrder` 用于拒绝违规计划。
- 「解析库不承担打包」：`apk` 无任何签名/打包 API；签名只作为 `BuildStep::Apksigner` 计划项出现在本库，且本轮不执行（`architecture.md` §8）。
- 与 `moon_abi` 是**数据契约（配置片段文本），不是 import**（K5）。

## 公开接口（速览）

`plan_build(config, abis)` · `render_script(plan)` · `verify_artifact(plan, artifact)` · `ci_gate_plan()`。完整签名见 `API.md`。

## 依赖

- **本轮零依赖**：无 `moon add`、未改 `moon.pkg`、无 FFI、无外部句柄。
- 后续轮（脚本**执行**，属组合根 / R4）：Android SDK build-tools（aapt2 / d8 / zipalign / apksigner）、NDK、JDK、adb——本库只输出命令模板文本，不执行。**SDK/NDK 二进制不可再分发**（Android SDK License 3.4），本库只分发计划与配置文本。
- `keystore_ref : String` 只存**引用**，禁止内嵌密钥材料（`MoonAndroidError::KeyMaterialEmbedded` 是可观察的拒绝信号）。

## 平台与许可风险

| 风险 | 说明 |
|---|---|
| 工具链无 Android 目标 | 必须走「C stub + 宿主 NDK/CMake」；`foreign_library` 不能导出可链接 `.so/.dll`（`[事实]`） |
| 版本未锁 | `ToolchainVersions` 任一字段为空视为未锁定，CI 必须拒绝（`ToolchainNotLocked`）；本轮 pin `moon 0.1.20261104` / `moonc v0.10.20+65efd5b93`（ADR-0010） |
| 密钥 | 签名密钥不入库；`KeyMaterialEmbedded` 显式拒绝 |
| 门禁 | `Gate::CheckDenyWarn` 已列入建议序列；R1 期曾按 ADR-0007 豁免（`0068` 会升级为 error），**R2 准备轮起实现完成、`0068` 归零，四道门禁统一含 `moon check --deny-warn`（11/11 拒警告通过）** |
| 主机差异 | Windows JDK 探测、32/64 位双 ABI so 管理属组合根 / 后续轮（本库不探测 JDK，`ToolchainNotLocked` 只校验锁定值） |
| 许可 | SDK/NDK 构件不可再分发；`create-...-app` legacy 模板只作参照 |

## 测试与验收

- **纯测（桌面 CI 可跑）**：步骤顺序断言（zipalign 早于 apksigner）；版本锁缺失 → `ToolchainNotLocked`；包名非法 → `InvalidPackage`；密钥内嵌 → `KeyMaterialEmbedded`；签名方案冲突 → `SigningSchemeConflict`；`render_script` 确定性双次比对；`verify_artifact` 元数据不符 → `ArtifactMismatch`。
- **验收标准**：从 `moon build` 到目标设备（红米电视 Android 9 / armeabi-v7a / 2GB）应用启动一条命令（依赖 E3 + Q1，未复现）；CI 四道门禁全绿（✅ R2 准备轮实跑：`moon check --deny-warn` / `moon build` / `moon test` / `moon fmt --check`，39 tests）。
- **门禁实跑（R2 准备轮，2026-11-07）**：`moon clean` → `moon check --deny-warn` → `moon build` → `moon test`（**39 tests** 全过）→ `moon fmt --check`，全部 exit 0；无链接期阻塞（无 FFI）。MVL-D 仍依赖 Q1 资产定位与 E3 实验结论。

## 当前状态 / 本轮产物

| 项 | 状态 |
|---|---|
| `moon_android.mbt`：值类型 ×12、`BuildPlanner` trait、`MoonAndroidError`（9 构造）、API ×4（真实实现） | ✅ |
| `pkg.generated.mbti` API 快照（与源码对账一致） | ✅ |
| 命令模板（`render_script` 产出可审阅文本）/ 脚本执行 / 签名 / adb / 双 ABI 模板泛化 | 命令模板 ✅；执行、签名、adb、模板泛化 ❌ 非目标或后续轮（R4） |
| 四道门禁：`moon check --deny-warn` / `moon build` / `moon test` / `moon fmt --check` | ✅ 全绿（39 tests） |

## 文档索引

`DESIGN.md` · `API.md` · `../docs/architecture.md` §2 / §6 L4 / §7 / §8 · `../docs/adr/ADR-0005`（排序 O6）、`ADR-0007`（R1 期门禁豁免，R2 准备轮起恢复 `--deny-warn`）、`ADR-0010`（零依赖与版本锁） · `../docs/roadmap-v2.md` R1/R2/R4 · `../docs/open-questions.md` E3 / Q1 / 决策点 5、7
