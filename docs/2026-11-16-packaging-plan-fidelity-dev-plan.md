# moon_android 打包计划保真与安全加固开发文档

> 建立：2026-11-16 ｜ 状态：**已实施完成（W1–W9 全部落地，2026-11-16 终验全绿）** ｜ 适用仓库：本仓库（独立自包含）
> 实施注记：2026-11-16 用户「采纳推荐」批准 W2-A/W3-A/W5-A/W8-A 全部裁决项；W1–W9 按里程碑顺序实施完毕，`moon test` 110/110（wasm 与 native parity），逐包簿记见 [CHANGELOG.md](CHANGELOG.md)。下方 §0 基线为开发前历史快照，保留作证据。
> 配套文档：[2026-11-16-test-system-design.md](2026-11-16-test-system-design.md)（验收测试 ID `T-W*-*` 出自该文档）
> 本文所有「现状」结论均为 2026-11-16 对本仓库源码的实测核对，非转述历史文档。
> 五门禁 2026-11-16 实跑：`check --deny-warn` 退出码 0；`build` 退出码 0；`test` **79/79 通过、0 条 #skip**（wasm）；`fmt --check` 退出码 0；`moon info` 后 `pkg.generated.mbti` 与 `cmd/main/pkg.generated.mbti` 快照 diff 为空。另实测 `moon test --target native` 亦 **79/79**（双目标等价，B2）。

## 0. 现状基线（实测核对，开发前必读）

| # | 事实 | 证据位置 |
|---|---|---|
| B1 | 公开面实测：14 pub fn / 24 pub(all) 值类型（15 struct + 9 enum）/ 14 错误变体 / 1 trait（`BuildPlanner`）。README §3 API 索引**漏列 `pub trait BuildPlanner`**（漂移） | `pkg.generated.mbti` 全文；`README.md` §3 |
| B2 | 五门禁全绿（2026-11-16 本机实测，wasm）；native 后端测试亦 79/79；全仓库 `#skip` 计数为 0 | 本机实跑；`grep '#skip' *.mbt` 零命中 |
| B3 | 测试声明数实测 79（8 个测试文件：25+14+10+1+13+3+11+2），与 README「79/79」一致；Git 提交数实测 **18**，仓库外申报材料称 17（计数漂移，需在仓库外材料侧修正） | `Select-String '^test '` 分文件计数；`git rev-list --count HEAD` = 18 |
| B4 | `plan_build` 恒产出规范 10 步（`canonical_steps()`），`InvalidStepOrder` 从 `plan_build` **不可达**；该变体仅经 `render_script` / `render_template_script` 对手造/篡改计划可达。README §1「plan_build …违规抛 InvalidStepOrder」表述误导（漂移） | `moon_android.mbt` `canonical_steps`/`validate_step_order`/`plan_build`；`moon_android_test.mbt` L518 负例走 `render_script` |
| B5 | `ToolchainVersions` 实测 **8 字段**：7 个必锁（moon_cli/moonc/core/ndk/build_tools/platform/jdk，任一为空 → `ToolchainNotLocked`）+ 可选 `cmake : String?`（缺失 → `MissingTool`）。代码注释与实现一致；仓库外申报材料「7 字段版本锁」措辞不精确 | `moon_android.mbt` L51-60、`first_unlocked_field` L306-329、`tool_version` L352-380 |
| B6 | 密钥引用制四入口拒绝 `KeyMaterialEmbedded` 属实：`plan_build`（L790）、`render_script` 经 `plan_steps_text`（L829）、`plan_template` 经 `plan_build`（L457）、`render_template_script`（L537） | `moon_android.mbt`；`template.mbt` |
| B7 | G-1 修复在码：Assemble 先 `mkdir -p out/native/<abi>/lib/<abi>` + `cp`，再 `$JAR uf … -C <dir> lib/<abi>/<soname>` 入包 | `moon_android.mbt` `command_lines` Assemble 分支 L711-735 |
| B8 | `verify_artifact` 实际语义：path 与计划 Apksigner 产物名比对；size 仅非零检查；sha256 仅 64 位十六进制**规格**检查；ABI/签名多重集合与计划比对。计划中**无**期望 size/sha256 字段，故「size/sha256 与计划一致」不成立——仓库外申报材料该句过度声称（漂移） | `moon_android.mbt` `verify_artifact` L922-968 |
| B9 | `MissingGate(Gate)` 在库代码中**零 raise 点**（死变体）；唯一触发是 whitebox 测试人工 raise。API 冻结下不可删除，须声明为保留变体 | `moon_android.mbt` L140；`moon_android_wbtest.mbt` L45-47、L253-256 |
| B10 | `BuildConfig.extra_native_libs` 仅被原样复制进生效配置（L816），全库**零消费**（不参与校验/渲染）→ 死字段（真缺口） | `grep extra_native_libs`：仅声明、复制与测试夹具空数组 |
| B11 | `min_sdk`/`target_sdk` 无范围与次序校验（负值、min>target 均放行，仅 min_sdk<24→V1 规则）；`entry_url` 无 scheme 校验（WebView 壳缺 entry_url 也放行）→ 真缺口 | `moon_android.mbt` `plan_build`/`validate_signing`；`template.mbt` `render_manifest` |
| B12 | 渲染脚本**无 `set -e`/`set -eu`**：资产阶段 `echo '<sha>  <src>' \| sha256sum -c -` 失败后下一行 `cp` 仍会执行（fail-open）。「先校验后复制」仅顺序成立、**阻断不成立**（安全缺口） | `template.mbt` `render_template_script` 阶段 3 L637-656；`render_script` 头 L909 |
| B13 | HEAD 提交 f304de0（2026-11-16）删除 docs/ 全部五份旧文档后遗留**悬空引用**：`template.mbt` L11/L64 → `docs/TEMPLATE.md`；`jdk.mbt` L15 → `docs/EXECUTION-CHAIN.md`；`moon_android_test.mbt` L6 → `docs/DECISIONS.md`；`ci.yml` L17/L23/L119 → `docs/DECISIONS.md`、`docs/API.md`（漂移，ci.yml 再次命中历史高发点） | `git show --stat f304de0`；目录实测无 docs/；grep 命中 |
| B14 | `cmd/main` 为模板 `Hello`，无实际 CLI（与 README §5 一致）；CLI 契约/退出码矩阵当前不适用 | `cmd/main/main.mbt` |
| B15 | 零第三方依赖（`moon.mod` 无 import 声明；mbti 仅 import `moonbitlang/core/debug`）；`preferred_target = "wasm"`；Apache-2.0 | `moon.mod`；`pkg.generated.mbti` L4-6 |
| B16 | 错误变体簿记：14/14 变体均有显式断言变体名的测试（grep 命中 3–21 处不等）；`MissingGate` 仅 whitebox 人工触发（见 B9） | `Select-String` 逐变体计数；各 `_test.mbt`/`_wbtest.mbt` |
| B17 | 两处内联 golden：`render_script` 全文快照（`moon_android_test.mbt` L402 起）、`render_template_script` 单 ABI 快照（`template_test.mbt` L378 起）；双次渲染确定性用例齐备 | 同左 |
| B18 | `probe_jdk`：version=None 按存在性接受是**明示的 fail-open 设计**（注释 L274「需组合根提供版本才严格」）；`required_major` 限 8..99 → `InvalidJdkProbe`；优先级/去重/大小写归一化/引号剥离均有测试矩阵 | `jdk.mbt` L269-409；`jdk_test.mbt` 11 例 |
| B19 | `jdk_major` 数字累加循环**无位数上限**：≥10 位数字版本号会 Int32 回绕，理论上可伪匹配 `required_major`（输入安全缺口） | `jdk.mbt` `jdk_major` L197-223 |
| B20 | 注入/穿越防护在码且有测试：heredoc 分隔符整行冲突拒绝（`contains_line`）、`relative_path_ok` 拒 `..`/盘符/反斜杠/空段、`valid_soname` 拒连续点号与分隔符、`xml_escape` 五字符 | `template.mbt` L86-291；`native_abi.mbt` L48-79；`template_test.mbt` L569/L640 |
| B21 | 渲染的 apksigner 命令使用 `--v31-signing-enabled`：**官方 apksigner 无此 flag**（官方 flag 面为 v1/v2/v3/v4-signing-enabled + `--rotation-min-sdk-version`，2026-11-16 联网核实官方文档）；且未传 `--min-sdk-version`/`--max-sdk-version`（计划已知该值）→ 命令模板保真真缺口 | `moon_android.mbt` `command_lines` Apksigner 分支 L740-758；官方 apksigner 文档 flag 清单 |
| B22 | 自包含扫描：无工作区路径/兄弟模块**文件**引用；`template.mbt` L171 注释示例以兄弟工作区模块坐标作样例值（测试字面量与 golden 含同坐标）。属样例坐标而非文件引用，低风险措辞项：注释可零成本中性化，测试字面量改动会扰动 golden（随 W2/W3 重录轮处理或保留） | `template.mbt` L171；`template_test.mbt` L30/L446 等 |
| B23 | `Gate` 7 变体、`ci_gate_plan()` 固定七项顺序属实且有测试；ci.yml 五门禁 + 工具链版本断言与 README 复验序列一致 | `moon_android.mbt` L976-986；`moon_android_test.mbt` L737；`.github/workflows/ci.yml` |
| B24 | `render_cmake` 的 cmake=None 回退分支（默认 "3.22.1"）经 `plan_template` 不可达（`plan_build` 已强制 cmake 锁定否则 `MissingTool`）→ 防御性死分支，无害，保留 | `template.mbt` L364-367；`moon_android.mbt` `validate_tools` |
| B25 | 测试夹具 `build_tools: "34.0.0"`/`platform: "android-34"`/`jdk: "17"` 与版本锁口径一致；README §6「本机 build-tools 35.0.0 与锁值差距」为环境事实 [需本地复核] | `moon_android_test.mbt` `locked_toolchain` L7-18；`README.md` §6 |

**对历史口径的修正**：
1. 申报材料「17 条有效提交」→ 实测 **18**（B3；仓库外材料侧修正）。
2. 申报材料「ToolchainVersions 7 字段版本锁」→ 结构体 **8 字段**（7 必锁 + 1 可选，B5）。
3. 申报材料「verify_artifact 校验……size/sha256……与计划一致」→ size/sha256 仅规格检查，计划无期望值可比（B8）。
4. README「plan_build 违规抛 InvalidStepOrder」→ 该变体仅渲染入口对篡改计划可达（B4）。
5. README §3 API 索引漏 `BuildPlanner` trait（B1）；docs/ 删除后 7 处悬空引用（B13）。
6. 「资产 SHA-256 先校验后复制」→ 顺序成立但脚本无阻断语义，校验失败仍复制（B12，本轮最重要安全修正）。
7. 渲染脚本 apksigner `--v31-signing-enabled` 为伪 flag（B21）。

## 1. 硬约束（每个工作包都必须满足）

1. **API 冻结**：`pkg.generated.mbti` 为冻结基线，只允许纯加法（新 pub fn / 新 struct / 新 enum）；禁止给既有 `pub(all)` struct 加字段；禁止新增错误变体（四件例外流程：ADR + 用户裁决 + CHANGELOG + 主版本）；校验失败用**值字段**（Bool/报告 struct）表达，解析失败复用既有 14 变体；语义变更走**新函数新类型防火墙**，旧 API 语义永不改变。
2. **加法三件套**：快照随源码同提交且 diff 纯加法 + CHANGELOG 登记 + CI 快照门禁绿。
3. **依赖不动**：本模块零第三方依赖（仅 core/test，B15），任何工作包不得引入新依赖；工具链版本锁（build-tools 34.0.0 / android-34 / JDK 17 / cmake 3.22.1）不升级。
4. **许可红线**：第三方 APK/.so/模型不入库；真实样本只允许「仓库外本地路径 + SHA-256 登记 + 显式 SKIPPED」；入库测试资产用确定性生成器自产（本库测试全部为程序化构造，无文件 fixture，保持）。
5. **五门禁全绿才可合入**；`#skip` 不得写成通过。**fail-closed 修复例外**：以前静默放行的损坏/不安全输入现在拒绝属行为增强非契约破坏（错误变体集合不变），但须 CHANGELOG 显式登记 + 回归确认仅受影响样本变化；涉及 golden 文本变化的（W2/W3）须维护者**书面裁决后重录**（G-1 先例：缺陷修复，非静默改基线）。
6. **边界不变量（非目标）**：不执行打包命令、不产出 APK、不内嵌密钥材料、不替调用方做版本决策、不实现 Gradle/IDE 集成、不做文件 I/O 与哈希计算（采集/执行/算哈希均属组合根）；旧函数输出语义防火墙永不改变。
7. **文档自包含**：本仓库 docs/ 与代码注释/帮助文本/脚本不得引用、链接或假定可访问工作区其他目录。

## 2. 业界对标摘要（P2 结论，证据三级标注）

**渠道与限定**：2026-11-16 经公开 web 渠道（GitHub 生态页、Android/Bazel/Kivy 官方文档、技术社区）检索；mooncakes 站内搜索此前四轮实测不可用（422/SPA 无法穷举），本轮未重试站内搜索，**不冒充已穷举 registry**。「未见同类」结论限定为：MoonBit 语言 + 「纯值计划层（零 I/O）+ 密钥引用制 + fail-closed 清单 + 确定性渲染」组合语义 + 2026-11-16 时点 + 上述公开渠道。

| 能力（F#） | 本模块（B# 实测） | Gradle AGP（JVM） | cargo-apk / cargo-ndk（Rust） | p4a + buildozer（Python） | Bazel aquery（通用） | MoonBit raylib 脚手架 |
|---|---|---|---|---|---|---|
| F1 有序构建计划 | 规范 10 步纯值 + 全序校验（B4/B7） | 任务图 + 执行一体 [已知常识] | 隐式流程，无独立计划值 [需联网核实] | recipe 依赖图（graph.py），执行一体 [需联网核实] | 分析期 action 图，可查询不执行 [需联网核实] | 无计划层，Gradle 直执 [需联网核实] |
| F2 确定性脚本渲染 | DO NOT EXECUTE 头 + 双次逐字一致（B17） | 无（直接执行）[已知常识] | 无 [需联网核实] | 无 [需联网核实] | `--output=commands` 打印命令行；aquery_differ 差分 [需联网核实] | 无 [需联网核实] |
| F3 密钥引用制 | 四入口拒绝内嵌（B6） | keystore 属性文件，可内嵌口令 [已知常识] | 环境变量/参数传 keystore [需联网核实] | spec 可写口令路径 [需联网核实] | 不涉及 | Gradle signingConfig [需联网核实] |
| F4 签名方案校验 | min<24→V1、V31→V3、禁重复（B6/B21） | 按 minSdk 自动决定 [已知常识] | 调 apksigner 默认策略 [需联网核实] | 调 apksigner/jarsigner [需联网核实] | 不涉及 | 无显式校验 [需联网核实] |
| F5 工具链版本锁 | 7 必锁 + cmake 可选，缺即拒（B5） | 版本目录/lockfile [已知常识] | NDK 版本参数 [需联网核实] | recommendations.py 推荐版本 [需联网核实] | 工具链注册 [已知常识] | 模板写死版本 [需联网核实] |
| F6 包名校验 | 两段式 ASCII 规则（B4 证据链） | manifest 合并期校验 [已知常识] | 有 [需联网核实] | spec 校验 [需联网核实] | 不涉及 | 无 [需联网核实] |
| F7 ABI 目录名/反解 | 4 ABI 双向 + 双 ABI 基线（B20） | ABI splits [已知常识] | 4 target 映射 jniLibs [需联网核实] | archs.py [需联网核实] | 不涉及 | 双 ABI 写死 [需联网核实] |
| F8 产物元数据校验 | 值比对 Bool + 结构拒绝（B8） | 构建期自检 [已知常识] | 无独立 API [需联网核实] | 无 [需联网核实] | 不涉及 | 无 |
| F9 CI 门禁序列 | 7 项纯常量（B23） | 无内置声明 [已知常识] | 无 | 无 | 无 | 无 |
| F10 通用模板生成 | 6 文件纯值树 + XML 转义（B20） | 项目模板（IDE 侧）[已知常识] | 无 | bootstrap 模板 [需联网核实] | 不涉及 | 一次性脚手架（生成后不可再参数化）[需联网核实] |
| F11 四阶段模板脚本 | heredoc 防注入 + 资产登记（B12/B20） | 无 | 无 | 无 | 不涉及 | gradlew 直执 [需联网核实] |
| F12 .so 清单 fail-closed | 未登记哈希拒渲染（B16/B20） | 无等价声明层 [已知常识] | 无哈希登记 [需联网核实] | 无 [需联网核实] | 不涉及 | 无 |
| F13 资产注入校验 | 路径/哈希/重复 target（B20） | assets 目录直拷 [已知常识] | 无 | 无 | 不涉及 | 无 |
| F14 JDK 纯评估器 | 优先级/去重/主版本（B18/B19） | JVM 工具链探测（执行侧）[已知常识] | 无 | 无 | 无 | 无 |

- 证据等级：表内逐格标注；本模块列全部指向 B# 实测行。易变事实（各项目 star/维护状态/最新版本）一律 [需联网核实]，本文不给未验证精确数字。
- **最接近 1–3 名与重叠度**：① Bazel aquery（「只暴露计划/命令行、不执行」语义最接近，且有 aquery_differ 差分哲学；但属通用构建系统的查询视图，非 Android 专用独立库，重叠约 40%）；② cargo-apk（Android 专用配置→APK 面最接近，但执行一体，重叠约 35%）；③ p4a+buildozer（spec 配置 + 版本推荐，执行一体，重叠约 30%）。
- **差异化判断**：「纯值计划层（零 I/O、零依赖、wasm 可测）+ 密钥引用制 + fail-closed 哈希清单 + 确定性可审阅渲染」的组合在上述公开渠道未见同类（限定见上）。本库不是任何执行器的替代品，而是执行器上游的**可审计契约层**。
- **缺失能力清单**：已声明非目标 = 执行链/产出 APK/Gradle 集成/adb 交互/哈希计算（README §1，保持）；真缺口 = B10（死字段）、B11（SDK/URL 校验）、B12（脚本 fail-open）、B19（版本解析溢出）、B21（伪 flag 保真）；可选新增面 = B14（薄 CLI，须裁决）。

## 3. 边界裁决（P3 结论）

**本质职责（一句话）**：把 Android 打包流程编译成确定性、可校验的**纯值计划与可审阅脚本文本**——回答「做什么、按什么顺序、用哪些锁定版本、是否安全」，永不回答「执行它」。

**边界判据**：一个能力属于本库，当且仅当 (a) 输出停留在纯值/文本（零 I/O、零进程、零密钥材料），且 (b) 结论止步于「计划自洽性/安全性」，不产生下游执行结果。凡需读文件、算哈希、spawn 进程、设备交互者，一律归组合根。

| 灰区 | 判据结论 | 裁决 | 落点（W#） |
|---|---|---|---|
| `probe_jdk` 环境探测疑似 I/O | 界内（采集/评估已拆分，评估器纯值） | 冻结 + 归属声明：采集器属组合根；version=None fail-open 为明示设计，另加严格模式新函数（防火墙） | W6/W7 |
| `verify_artifact` 疑似读文件算哈希 | 界内（纯元数据值比对） | 冻结 + README 措辞修正（size/sha256 仅规格检查，B8） | W1 |
| `extra_native_libs` 死字段 | 界内但未接线 | 新函数接线（纯加法），旧 `plan_build`/渲染输出永不改变；零成本降级 = README 声明保留字段 | W5 |
| `MissingGate` 死变体 | 界内但无自然触发点 | 冻结 + 声明保留变体（不删、不强行接线制造伪触发） | W1 |
| `ci_gate_plan` 疑似项目管理结论 | 界内（声明式常量） | 冻结 + 声明「仅为建议序列，不代表 CI 实况」 | W1 |
| 渲染脚本 fail-open（B12） | 界内安全缺口（文本应表达 fail-closed 语义） | fail-closed 修复例外：`set -eu` 头 + golden 书面裁决重录 + CHANGELOG | W2（须裁决） |
| apksigner 伪 flag（B21） | 界内保真缺口 | 映射到官方 flag 面 + golden 书面裁决重录；零成本降级 = 注释标注伪 flag | W3（须裁决） |
| 执行链（aapt2/d8/… 执行、adb 安装） | **界外** | 不开包；归属组合根/未来独立模块，本库只渲染 | —（非目标登记） |
| `cmd/main` 薄 CLI | 界内可选（CLI 是组合根的最薄形态，只调纯函数 + 打印） | 须裁决：A 薄 CLI / B 保持 Hello / C 执行器 CLI（界外，否决） | W8（须裁决） |
| 注释中兄弟模块样例坐标（B22） | 低风险措辞（样例值非文件引用） | 注释中性化（零成本）；测试字面量/golden 坐标随重录轮处理或保留 | W1 |

## 4. 工作包总览

| 包 | 名称 | 优先级 | 规模 | API 影响 | 对应缺口（B#） |
|---|---|---|---|---|---|
| W1 | 漂移清理与簿记建立 | P0 | S | 无 | B1/B4/B8/B9/B13/B22/B23 |
| W2 | 渲染脚本 fail-closed 加固（须裁决） | P1 | S | 无（输出文本变化，golden 重录） | B12 |
| W3 | 签名命令模板保真（须裁决） | P1 | M | 无（输出文本变化，golden 重录） | B21 |
| W4 | SDK 范围与 entry_url 值化校验 | P2 | S | 加法：2 struct + 2 fn | B11 |
| W5 | extra_native_libs 新函数接线 | P2 | S | 加法：1 fn | B10 |
| W6 | jdk_major 溢出防护 | P1 | S | 无（fail-closed 行为增强） | B19 |
| W7 | probe_jdk_strict 严格模式 | P3 | S | 加法：1 fn | B18 |
| W8 | 薄 CLI（须裁决） | P3 | M | 无（库 API 零变化；cmd/main 重写） | B14 |
| W9 | 测试系统加固（性质/变异/门禁脚本） | P2 | M | 无 | B2/B16/B17 + P6 设计 |

## 5. 工作包详细设计

### W1 漂移清理与簿记建立（P0/S）

**目标**：消除 B13 全部 7 处悬空引用与 B1/B4/B8 措辞漂移，建立 CHANGELOG 簿记。
**非目标**：不改任何代码行为、不动 API、不重写 README 结构。
**新增 API**：无。
**实现要点**：
- `template.mbt` L11/L64、`jdk.mbt` L15、`moon_android_test.mbt` L6 注释中 `docs/*.md` 引用改为指向 `README.md` 对应章节（README 为唯一说明文档）；`ci.yml` L17/L23/L119 的 `docs/DECISIONS.md`/`docs/API.md` 引用改为 `README.md`（版本锁与冻结策略要点已在 README §2/§5）。
- README §3 索引补 `pub trait BuildPlanner { fn plan(Self) -> BuildPlan raise MoonAndroidError }`；§1 措辞改为「步骤全序约束在渲染入口对任意计划强制（违规抛 InvalidStepOrder）；plan_build 恒产出规范 10 步」；§1 能力行补「verify_artifact：path/ABI/签名与计划比对，size/sha256 仅规格检查」；§2 补「MissingGate 为保留变体（当前无库内触发点）」「ci_gate_plan 仅为建议序列」。
- README 首行「本文件是本仓库唯一说明文档」改为「本文件是本仓库唯一**说明**文档；docs/ 存放带日期的开发/测试设计文档与 CHANGELOG」（为本轮两份文档与 W1 新建簿记让位）。
- `template.mbt` L171 注释样例坐标中性化为 `author/name`、`author/name@0.1.2` 形式（B22；测试字面量不动）。
- 新建 `docs/CHANGELOG.md`，登记本轮文档与后续每包变更。
**验收**：T-W1-1（引用实存性扫描零悬空）、T-W1-2（README 索引 ↔ mbti 逐条一致含 trait）、T-W1-3（五门禁绿 + mbti 零 diff）、T-W1-4（CHANGELOG 实存且登记）。

### W2 渲染脚本 fail-closed 加固（P1/S，须裁决）

**目标**：消除 B12——渲染脚本在任一命令失败时继续执行后续命令（含哈希校验失败后仍复制资产）。
**非目标**：不改错误变体集合、不改库函数签名、不执行脚本。
**新增 API**：无（输出文本变化）。
**实现要点**：`render_script` 与 `render_template_script` 在 `#!/bin/sh` 之后插入 `set -eu` 一行（两入口共用渲染头助手，避免双份漂移）。资产阶段保持「校验行在前、复制行在后」，由 `set -eu` 提供阻断语义。
**冻结合规**：fail-closed 修复例外——以前静默放行的不安全执行流现在拒绝；错误变体集合不变；须 CHANGELOG 显式登记 + 回归确认仅受影响行变化 + **两处 golden 书面裁决后重录**（G-1 先例）。
**须裁决选项**：
- **A（推荐）**：`set -eu` 头。diff 最小（每脚本 +1 行），POSIX sh 通用，阻断全部命令失败。
- B：逐命令 `&&` 链接。diff 大、可读性差，但失败定位更细；不推荐。
- C（零成本降级）：保持现状，README 显式声明「脚本不具备失败阻断语义，执行方须自行 set -e」；安全缺口留档。
**验收**：T-W2-1…T-W2-6（见配套文档 §6.5）。

### W3 签名命令模板保真（P1/M，须裁决）

**目标**：消除 B21——`--v31-signing-enabled` 非官方 apksigner flag；补 `--min-sdk-version`/`--max-sdk-version` 使签名决策确定化。
**非目标**：不实现真实签名/轮换执行、不新增 SigningScheme 变体（V4 等属破坏性/新语义，须另走裁决，本轮不做）。
**新增 API**：无（输出文本变化）。
**实现要点**：`command_lines` Apksigner 分支：V1/V2/V3 维持 `--vN-signing-enabled true`；V31 不再渲染伪 flag，改为渲染官方语义注释行（`# V31 rotation: apksigner applies v3.1 block when rotation is configured; see --rotation-min-sdk-version`）+ 保留 `--v3-signing-enabled true`（V31 必伴 V3 已由校验保证）；命令追加 `--min-sdk-version \{config.min_sdk} --max-sdk-version \{config.target_sdk}`。
**冻结合规**：命令模板正确性修复；golden 书面裁决重录 + CHANGELOG；旧负例（密钥/顺序/工具）零改动。
**须裁决选项**：
- **A（推荐）**：上述保守映射 + 注释。渲染文本全部落在官方 flag 面内，轮换参数留给组合根。
- B（零成本降级）：保留伪 flag 但渲染注释明确标注「pseudo-flag，官方 apksigner 不识别，执行前须人工替换」；诚实但交付价值低。
- C：完整轮换 signer 配置模板（多 keystore 引用、rotation-min-sdk 参数化）。规模 L 且引入新配置面，本轮否决，留待执行链轮。
**验收**：T-W3-1…T-W3-6。

### W4 SDK 范围与 entry_url 值化校验（P2/S）

**目标**：消除 B11，以**值字段**表达校验结论（硬约束 1：校验失败值化，不新增错误变体）。
**非目标**：不改 `plan_build` 既有放行行为（防火墙：旧 API 语义永不改变）；不硬编码官方最新 API 级（易变事实）。
**新增 API（mbti 草案，纯加法）**：

```text
pub(all) struct SdkRangeReport {
  min_sdk_valid : Bool
  target_sdk_valid : Bool
  order_valid : Bool
  detail : String
}
pub fn check_sdk_range(BuildConfig) -> SdkRangeReport

pub(all) struct EntryUrlReport {
  required : Bool
  present : Bool
  scheme_ok : Bool
  detail : String
}
pub fn check_entry_url(BuildConfig) -> EntryUrlReport
```

**实现要点**：新文件 `config_check.mbt`。`check_sdk_range`：min/target ∈ 1..=100（文档明示 100 为**宽松健全上界**而非官方最大值 [需联网核实]）、min ≤ target；`check_entry_url`：WebView 壳 required=true，要求 Some 且 scheme ∈ {http, https, file}（大小写不敏感），其余壳 required=false 恒真。两函数零 raise、纯计算。调用方（组合根/CLI）自行决定是否据报告拒绝。
**验收**：T-W4-1…T-W4-4。

### W5 extra_native_libs 新函数接线（P2/S）

**目标**：消除 B10 死字段，提供独立接线入口；旧渲染输出永不改变。
**非目标**：不在 `plan_build`/`command_lines` 中消费该字段（那会改变旧输出，违反防火墙）。
**新增 API（mbti 草案，纯加法）**：

```text
pub fn plan_extra_native_libs(Array[String], Array[Abi]) -> Array[NativeLib] raise MoonAndroidError
```

**实现要点**：落 `native_abi.mbt`。复用 `validate_abis`（空/重复 → `UnsupportedAbi`）与 `valid_soname`（非法 → `InvalidNativeLib`）；soname 重复 → `InvalidNativeLib("重复的 extra soname：…")`；产出 `sha256=None` 条目，与 `attach_native_hashes`/`validate_native_manifest` 天然互操作。README 声明：该字段由组合根经本函数消费，`plan_build` 不自动入包。
**须裁决选项**：**A（推荐）** 新函数接线；B（零成本降级）README 声明 `extra_native_libs` 为保留字段、本轮不接线。
**验收**：T-W5-1…T-W5-5。

### W6 jdk_major 溢出防护（P1/S）

**目标**：消除 B19——超长数字版本号 Int32 回绕可伪匹配。
**非目标**：不改正常版本（≤9 位）解析结果；不改 `probe_jdk` 签名。
**新增 API**：无。
**实现要点**：`jdk_major` 主/次版本数字累加各设 9 位上限，超限返回 None（fail-closed：不可解析 ≠ 匹配）。`probe_jdk` 对 None 已有「版本无法解析 → 不匹配」路径，自动承接。
**冻结合规**：fail-closed 修复例外——仅病态输入（≥10 位）行为变化；CHANGELOG 登记 + 回归确认正常语料输出逐字不变。
**验收**：T-W6-1…T-W6-4。

### W7 probe_jdk_strict 严格模式（P3/S）

**目标**：为 B18 明示的 fail-open（version=None 按存在性接受）提供 fail-closed 替代入口。
**非目标**：不改 `probe_jdk` 任何行为。
**新增 API（mbti 草案，纯加法）**：

```text
pub fn probe_jdk_strict(JdkProbeEnv) -> JdkProbeResult raise MoonAndroidError
```

**实现要点**：`jdk.mbt` 内部评估器提取 strict 参数（私有重构，旧输出逐字节不变）；strict 下 version=None → 不选中 + 诊断「版本未提供（严格模式拒绝）」；状态机与 `required_major` 校验复用（`InvalidJdkProbe`）。
**验收**：T-W7-1…T-W7-4。

### W8 薄 CLI（P3/M，须裁决）

**目标**：把 B14 的 Hello 模板替换为可演示的薄 CLI，作为组合根最薄形态。
**非目标**：不执行打包、不读密钥文件、不做 JSON 解析（零依赖约束下不引解析库）；库 API 零变化。
**新增 API**：无（`cmd/main` 为 executable，mbti 无 pub 面）。
**实现要点**：flag 驱动子命令 `gates` / `render` / `template` / `probe-jdk`；配置经 flag 传入（包名/ABI/签名/min/target/keystore-ref），工具链版本用内置锁常量（与测试夹具同值）；错误通道 `Result[T, String]`（库错误经 catch 归一为变体名文本，遵循跨包只读约束）；退出码矩阵 **0 成功 / 1 校验失败（stderr 打印变体名）/ 2 用法错误**；stdout 只输出渲染文本/门禁清单，永不输出密钥材料。
**须裁决选项**：
- **A（推荐）**：上述薄 CLI。演示价值高、纯加法、退出码契约一次冻结。
- B（零成本降级）：保持 Hello，README 维持「以 API 与渲染文本对外」。
- C：执行器 CLI（调 aapt2/zipalign/…）——**界外，否决**（P3 判据）。
**验收**：T-W8-1…T-W8-6。

### W9 测试系统加固（P2/M）

**目标**：落地配套测试系统设计文档的 L1 性质层、变异自检、双目标 parity 与错误簿记门禁。
**非目标**：不改库代码；不引入第三方测试框架。
**新增 API**：无。
**实现要点**：新增性质测试（变形律 P1–P10，见配套文档 §4）入既有 `_test.mbt`/`_wbtest.mbt`；新增 `tools/parity.sh`（wasm/native 双跑 + 输出 diff）、`tools/mutation-selfcheck.sh`（3 类缺陷注入必须变红后还原复绿）、`tools/ref-scan.sh`（引用实存性 + README 索引核对）；字符串变异语料（路径/包名/版本号/哈希，固定种子 ≥1000 变异体）进 wbtest。脚本自包含、不引用仓库外路径。
**验收**：T-W9-1…T-W9-5。

## 6. 里程碑与合入顺序

```text
M0（第1日）  W1 漂移清理 + CHANGELOG（零风险，先行）
M1          W2 + W3（安全/保真，须书面裁决 golden 重录）+ W6（溢出防护）
M2          W4 + W5 + W9（高价值低成本能力与测试加固）
M3          W7（严格模式，可选）
M4（裁决后） W8（薄 CLI，若裁决选 A）
```

排序判据：先零风险文档、再安全缺口、再高价值低成本、最后可选新面；每包独立提交、独立过五门禁；W2/W3 的 golden 重录须维护者书面裁决（G-1 先例），未裁决前不合入。

## 7. 簿记与变更管理

- `docs/CHANGELOG.md`（W1 建立）：每包登记「日期 / 工作包 / 新增 pub 声明 / 快照 diff 结论 / 测试增量 / fail-closed 或 golden 重录裁决记录」。
- README API 索引随 `moon info` 快照同步（禁手编 mbti）；W1 后索引含 trait。
- 破坏性需求（新错误变体、既有 struct 加字段、V4 签名语义等）一律走四件例外流程，本轮零此类需求。
- 仓库外申报材料的计数/措辞修正（B3/B5/B8）由材料维护方执行，不在本仓库工作包内。

## 8. 完成定义（DoD，逐包勾选）

- [ ] 新增 API 与 mbti 草案一致（偏差回写本文）
- [ ] 快照 diff 纯加法，CHANGELOG 已登记
- [ ] T-W*-* 验收全绿；#skip 显式标注原因
- [ ] 五门禁全绿；CLI 对外契约零意外漂移（W8 若落地：退出码矩阵 0/1/2 逐例断言）
- [ ] 防火墙回归：新函数合入后旧 API 在既有语料上输出逐字节不变 / 旧用例零改动全绿（纯文档包 W1 豁免；W2/W3 仅限书面裁决的 golden 行变化）
- [ ] 畸形语料无 panic（新增解析路径进截断/变异扫描）
- [ ] 零新第三方依赖；零许可不明二进制入库
- [ ] README 能力/非目标同步；本文状态行更新「已交付+日期」

## 9. 风险登记

| 风险 | 等级 | 缓解 |
|---|---|---|
| W2/W3 golden 重录被误用为静默改基线 | 高 | 书面裁决 + CHANGELOG + 回归 diff 仅限预期行（G-1 先例流程） |
| `set -eu` 改变组合根既有执行习惯（如依赖未定义变量） | 中 | 渲染头注释明示语义；W8 CLI 不执行脚本，仅渲染 |
| V31 保守映射与未来真实轮换需求差距 | 中 | W3 选项 C 留档；执行链轮另议，不在本轮扩面 |
| SDK 上界 100 为健全值非官方值 | 低 | 文档明示 [需联网核实]；报告 struct 值化，调用方可覆盖决策 |
| 薄 CLI 退出码契约一次冻结后难改 | 中 | W8 须裁决；契约写入 README 与测试矩阵后再合入 |
| 密钥检测为启发式（可被无前缀裸 base64 绕过） | 中 | README 诚实声明「启发式防线，非密码学保证」；纵深防御归组合根 |
| 本机 build-tools 35.0.0 与锁值 34.0.0 差距（B25） | 低 | 真机轮统一；本轮文本层不受影响 |