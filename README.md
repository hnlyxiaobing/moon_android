# hnlyxiaobing/moon_android

**MoonBit → Android 打包链的「计划与配置」契约 —— 构建计划、工具链版本锁、CI 门禁序列与产物校验规格。**

> 状态：**R4（2026-11-09）模板泛化 / 双 ABI / JDK 纯评估器已落地**。24 个值类型、`BuildPlanner` trait、`MoonAndroidError`（14 构造）与 14 个公开函数全部为真实实现（0 条 `0068`）；五道门禁 `moon check --deny-warn` / `moon build` / `moon test`（**79 tests**）/ `moon fmt --check` / 快照门禁全绿（本机等价实跑）。**无脚本执行、无签名、无 adb、无 APK 读写**。
> `preferred_target = "wasm"`（骨架原值，未改动）；全后端、桌面可测。
> **与骨架 README / 报告定位差异**：骨架把本项目定为 **「先解决能出包」的起点**；本仓库按「先验证再抽象」的排序决策（见 `DECISIONS.md` 决策 2）在 R1-R3 只做计划/配置，R4 才把**已被计划层验证的纯值接口**泛化为模板；设备端通路（E3/Q1）仍未实测，模板泛化**不**等于通路已验证。

## 排序修正（重要，完整理由见 `DECISIONS.md` 决策 2）

| 项 | 原报告 / 骨架 README | 本仓库路线 | 原因 |
|---|---|---|---|
| 优先级 | 「先解决能出包」的里程碑起点 | 计划/配置部分先行（桌面可测）；**模板泛化在 R4、设备通路验证之后仍待补** | 「先验证再抽象」：模板只固化已由计划层验证的纯值接口，不把未验证假设写成接口 |
| 首轮交付 | 泛化脚本 `moon android build --abi …` | R1-R3：计划/配置 + 一次性脚本作为验收基线；R4：`plan_template` / `render_template_script` 纯值模板 | 更小替代方案；一次性脚本足以证明「MoonBit 产物能在目标设备启动」（仍待实测） |
| 依赖 | 被推理 / 插桩任务硬依赖（NDK 交叉编译） | NDK 交叉编译**降级为上板软依赖** | C API `.so` 与插桩 devkit 都是预编译产物，桌面验证不需要 NDK |
| 影响 | 打包链阻塞其他任务 | FFI 模块可与打包链并行推进 | 上板时仍必须补 `moon_abi` 配置，**不能省略** |

**被替代方案**：直接做参数化模板 + WebView/GLES 双壳 Activity + 双 ABI so 管理。风险：若 Android native 产物链路（MoonBit → C 源码/对象 → NDK clang + CMake 产出可加载 `.so`）未跑通，模板全部作废；且作为验收基线的一次性打包脚本、真实 APK 与目标设备资产**均不在本仓库**，设备端最小验证目前无法在本仓库内复现（见「风险与待验证」）。

## 定位与为什么存在

`moon build --target` 只有 wasm / wasm-gc / js / native / llvm / all，**没有 android 目标**；官方「一门语言、多后端」未把 Android 集成列入目标；社区只有 JNI 桥接件，没有「一条命令出 APK」。可行路径是「C stub + 宿主 NDK/CMake + aapt2 / d8 / zipalign / apksigner」外围工具链。

**选「纯 MoonBit 自研（计划 + 配置）」**（选型判定见 `DECISIONS.md` 决策 6）：`create-moonbit-raylib-android-app@0.1.0` 是 legacy 模板（仍带 `moon.pkg.json`），只能作参照、不可直接依赖；本仓库零新增依赖。

## 能力范围 / 非目标

- **做**：由 `BuildConfig` 生成有序 `BuildPlan`（含步骤顺序校验）、渲染可审阅的脚本文本、校验产物元数据（size / sha256 / ABI / 签名方案）、给出建议的 CI 门禁序列；**R4 新增**：`plan_template` 生成目录树（包名/应用名/ABI/模块依赖/资产注入 → 6 个文件）、双 ABI `.so` 目录/清单/SHA-256 登记校验、Windows JDK 纯评估器（`probe_jdk`）。
- **不做**：**不执行任何外部命令**、不签名、不调 adb、不读写 APK、不实现 Gradle / IDE 集成、不管理密钥材料、**不读环境变量/注册表**（JDK 采集器属组合根）、不下载 SDK、不嵌入资产/`.so` 内容、不自动计算 SHA-256。
- 步骤顺序硬约束：`BuildStep::Zipalign` 必须在 `BuildStep::Apksigner` 之前（签名后任何改动都会使签名失效）；`InvalidStepOrder` 用于拒绝违规计划。
- 「解析库不承担打包」：`apk` 无任何签名/打包 API；签名只作为 `BuildStep::Apksigner` 计划项出现在本库，且不执行（`DECISIONS.md` 决策 4）。
- 与 `moon_abi` 是**数据契约（配置片段文本），不是 import**，名义类型隔离、消解潜在循环依赖（`DECISIONS.md` 决策 3）。

## 公开接口（速览）

**既有 4 个**：`plan_build(config, abis)` · `render_script(plan)` · `verify_artifact(plan, artifact)` · `ci_gate_plan()`。

**R4 新增 10 个**：`abi_dir_name` · `dual_abi_set` · `parse_abi_dir_name` · `plan_native_libs` · `attach_native_hashes` · `validate_native_manifest` · `render_native_manifest` · `plan_template` · `render_template_script` · `probe_jdk`。

完整签名、错误与边界见 `API.md`；模板映射见 `TEMPLATE.md`；执行链风险见 `EXECUTION-CHAIN.md`。

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
| 门禁 | `Gate::CheckDenyWarn` 已列入建议序列；早期实现未完成阶段曾临时豁免（`0068` 会升级为 error），**实现完成、`0068` 归零后豁免失效，五道门禁统一含 `moon check --deny-warn`** |
| 主机差异 | **R4 已实测**：`JAVA_HOME` 指向失效目录会让 `d8.bat`/`apksigner.bat` exit 1；本机 build-tools 35.0.0 / android-35 / JDK 21 与锁值（34.0.0 / android-34 / 17）不符；NDK 与 CMake 缺失 → 按锁定版本**当前不可执行**。JDK 采集器属组合根，库内只做纯评估（`EXECUTION-CHAIN.md` §3）`[已复验]` |
| 双 ABI | 清单/哈希 fail-closed：未登记哈希、缺失 ABI、重复 ABI、目录漂移均拒绝（`native_abi.mbt`）`[已复验]`（单元测试）；设备安装 `[仍需实测]` |
| 许可 | SDK/NDK 构件不可再分发；`create-...-app` legacy 模板只作参照 |

## 测试与验收

- **纯测（桌面 CI 可跑）**：步骤顺序断言（zipalign 早于 apksigner）；版本锁缺失 → `ToolchainNotLocked`；包名非法 → `InvalidPackage`；密钥内嵌 → `KeyMaterialEmbedded`；签名方案冲突 → `SigningSchemeConflict`；`render_script` 确定性双次比对 + golden；`verify_artifact` 元数据不符 → `ArtifactMismatch`；**R4**：双 ABI 目录/清单/哈希与错误路径、模板生成树 + XML 转义 + 篡改树拒绝 + 脚本 golden、JDK 优先级/去重/版本匹配/错误路径。
- **验收标准**：从 `moon build` 到目标设备（红米电视 Android 9 / armeabi-v7a / 2GB）应用启动一条命令（E3/Q1，未复现，`[仍需实测]`）；五道门禁全绿（✅ 2026-11-09 本机等价实跑：**79 tests**）。
- **门禁实跑（2026-11-09）**：`moon check --deny-warn` → `moon build` → `moon test`（**79 passed / 0 failed**）→ `moon fmt --check` → `moon info` + `git diff --exit-code -- pkg.generated.mbti cmd/main/pkg.generated.mbti`，全部 exit 0；无链接期阻塞（无 FFI）。设备端最小验证仍依赖 Q1/E3 结论与真机。

## 风险与待验证

- **Android native 产物链路（最高优先级待验证假设）**：「MoonBit → C 源码/对象 → NDK clang + CMake」能否产出可加载 `.so`（native `foreign_library` 不能导出 `.so`）——这是设备端交付通路的前提，开发期报告称手工跑通但**本仓库无复现证据**。最小实验：最小 MoonBit 模块 + 一个 C stub，NDK clang 编出 `.so`，塞进 shell APK，在设备上加载并打印。
- **设备端最小验证资产缺失**：「从 `moon build` 到应用启动一条命令」的验收基线依赖一次性打包脚本、真实 APK 与目标设备（红米电视）资产，**均不在本仓库**，当前无法在本仓库内复现。
- **执行链环境缺口（R4 实测）**：`JAVA_HOME` 失效、build-tools/platform/JDK 与锁值不符、NDK/CMake 缺失 → 按锁定版本不可执行；属环境与版本锁流程（ADR-0010 §4），不是库代码缺陷。详见 `EXECUTION-CHAIN.md` §3。
- **已知缺口 G-1（待主控裁决）**：既有 `render_script` 的 Assemble 行把 `.so` 放在 APK 根而非 `lib/<abi>/`；按红线 4 只书面登记、不静默重录既有 golden。详见 `EXECUTION-CHAIN.md` §6。
- **CMake target 名**：模板以 target = soname、`OUTPUT_NAME` = stem 对齐计划命令；本机无 cmake，`[仍需实测]`。
- legacy 模板迁移后的可编译性未验证（`create-moonbit-raylib-android-app` 仅作参照）。

## 当前状态 / 本仓库产物

| 项 | 状态 |
|---|---|
| `moon_android.mbt` / `native_abi.mbt` / `template.mbt` / `jdk.mbt`：值类型 ×24、`BuildPlanner` trait、`MoonAndroidError`（14 构造）、公开函数 ×14（真实实现） | ✅ |
| `pkg.generated.mbti` API 快照（R4 纯加法，无既有签名改动） | ✅ |
| 命令模板（`render_script`）/ 模板生成树与四阶段脚本（`render_template_script`）/ 双 ABI 清单 / JDK 纯评估器 | ✅ |
| 脚本执行 / 签名 / adb / Gradle / IDE / 真实 `.so`、资产、模型入库 | ❌ 非目标（红线：真实库与资产不入库） |
| 五道门禁：`moon check --deny-warn` / `moon build` / `moon test` / `moon fmt --check` / 快照门禁 | ✅ 全绿（79 tests，2026-11-09 本机等价实跑） |
| 执行链本机跑通 / 设备启动 | ❌ `[仍需实测]`（环境缺口见 `EXECUTION-CHAIN.md`） |

## 文档索引

`DESIGN.md`（设计契约）· `API.md`（公开接口）· `DECISIONS.md`（设计决策记录）· `TEMPLATE.md`（模板 → 生成目录树映射）· `EXECUTION-CHAIN.md`（执行链风险评估、JDK 探测与已知缺口）
