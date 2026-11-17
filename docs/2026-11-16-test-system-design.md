# moon_android 测试系统设计（第一性原理）

> 建立：2026-11-16 ｜ 状态：**已全部落地（W1–W9 验收完成，2026-11-16 终验 110/110）** ｜ 适用仓库：本仓库（独立自包含）
> 实施注记：T-W*-* 验收项随 W1–W9 全部落地；实跑证据：双目标 parity 110/110、变异自检 3/3 缺陷变红还原复绿、ref-scan 14/14 簿记、cli-smoke 13/13 PASS；逐包簿记见 [CHANGELOG.md](CHANGELOG.md)。下方基线为开发前历史快照，保留作证据。
> 配套文档：[2026-11-16-packaging-plan-fidelity-dev-plan.md](2026-11-16-packaging-plan-fidelity-dev-plan.md)（`T-W*-*` 验收 ID 一一对应）
> 现状基线：2026-11-16 实测五门禁全绿，`moon test` 79/79（wasm）与 79/79（native），零 #skip；B# 证据行见配套文档 §0。

## 1. 第一性原理：本库的正确性是什么

本库的数学形态：`Config × Abis → (Plan, ScriptText, VerifyBool, ProbeResult) | MoonAndroidError`，全程纯计算、零 I/O。
正确性不可约简为以下断言，每条必须有测试层承载：

| # | 断言 | 含义 | 反例（测试必须抓住） |
|---|---|---|---|
| A1 | 渲染保真 | 脚本文本与计划值一一对应；命令模板落在官方工具真实 flag 面内；步骤顺序/输入输出/版本锁逐行忠实 | `--v31-signing-enabled` 伪 flag（B21 已抓住）；渲染行与 plan.steps 错位 |
| A2 | 完整性 fail-closed | 可校验项不一致必被报告；未登记哈希 ≠ 通过；校验失败必须阻断后续危险动作 | 未登记 sha256 仍渲染清单；`sha256sum -c` 失败后仍 `cp`（B12 已抓住） |
| A3 | 边界纯净 | 只输出声明的纯值/文本；零 I/O、零进程、零密钥材料泄漏；不产出执行结果 | 渲染文本含 keystore 口令；函数偷偷读文件 |
| A4 | 输入安全 | 任意畸形字符串不 panic/不越界/整数不回绕伪匹配；路径不逃逸 | ≥10 位版本号 Int32 回绕伪匹配（B19）；`../` 穿越；heredoc 分隔符注入 |
| A5 | 契约稳定 | mbti 只加法；14 错误变体集合冻结；golden 确定性；退出码矩阵（若 W8 落地）不变 | 新包偷偷改旧函数输出；新增错误变体 |
| A6 | 平台等价 | wasm 与 native 同输入同输出（含渲染文本逐字节） | 某后端 Char/Int 语义差异导致渲染分叉 |

设计推论：A1/A2 → 性质测试 + 官方文档静态 oracle + 穷举扫描；A2 语义 → 恒等式断言 + 错误簿记；A4 → 字符串变异语料 + 边界值矩阵；A5/A6 → 门禁与差分；真实工具符合性 → L3 外部 oracle 层（许可约束下本地可选）。本库无二进制解析面，「截断扫描」裁剪为**字符串全前缀/变异扫描**（路径、包名、版本号、哈希、soname）。

## 2. 测试分层

```text
L0 单元与程序化 fixture（每个 pub fn 行为样例）——现状 79 例主体
L1 性质与变异（变形律 P1–P10 / 字符串变异 / 边界值）——W9 待建
L2 受控黄金差分（内联 golden 全文快照）——现状 2 处
L3 外部 oracle 差分（官方 apksigner/aapt2/zipalign CLI 形态，本地可选 SKIPPED）——W3/W9 待建
L4 CLI 场景 E2E（退出码矩阵 0/1/2）——W8 裁决后待建；当前无 CLI（B14）
L5 元契约门禁（快照/错误簿记/双目标等价/变异自检/引用实存性）——部分在码（ci.yml），脚本层 W9 待建
R  真实样本本地 runner（仓库外 .so/APK 路径 + SHA-256 门禁 + 显式 SKIPPED）——设计保留，当前零样本
```

断言×层承载表：

| 断言 | 主承载层 | 辅助层 |
|---|---|---|
| A1 渲染保真 | L2 golden + L3 静态 oracle | L0 内容断言、L1 P8 |
| A2 fail-closed | L0 负例 + L1 恒等式 | L5 错误簿记 |
| A3 边界纯净 | L0 密钥泄漏断言 | L5 变异自检（注入泄漏缺陷必须变红） |
| A4 输入安全 | L1 变异/边界矩阵 | L0 畸形负例 |
| A5 契约稳定 | L5 快照门禁 + 防火墙律 P7 | L2 golden |
| A6 平台等价 | L5 parity 脚本 | 双目标 moon test |

## 3. fixture 体系

| 类 | 形态 | 入库 | 许可 | 现状 |
|---|---|---|---|---|
| F-A 程序化构造 | 测试代码内 `locked_toolchain`/`demo_config`/`good_sha256`/`raw_plan` 等 builder | 是 | 随仓库 | 在码，全部测试唯一依赖（B17） |
| F-B 受控文件 fixture | tests/fixtures/* | — | — | **本模块无文件 fixture**（纯值库，保持零文件依赖） |
| F-C 生成器资产 | 确定性脚本产出 | 是 | 自产 | W9 变异语料由固定种子生成器在测试内产出，不落盘 |
| F-D 真实第三方样本 | 仓库外本地 .so/APK | 否（红线） | 许可不明 | R runner 设计保留；当前零样本、零 SKIPPED |

红线：F-D 永不入库；本库不算哈希，R runner 的哈希由组合根计算后与登记值比对，不符拒绝执行。
builder 能力清单（现有 + W9 扩展）：
- 配置维度：包名（合法/单段/非法字符/空）、ABI 集（空/重复/1–4 个）、签名集（空/重复/缺 V1/缺 V3）、min/target（负值/0/24 边界/min>target/超上界）、keystore_ref（正常引用/六类密钥信号）、toolchain（逐字段置空/cmake None）、entry_url（None/http/https/file/ftp/空串）。
- 清单维度：soname（合法/穿越/连续点号/分隔符/空 stem）、dir 漂移、sha256（None/63 位/65 位/非 hex/大写）。
- JDK 维度：路径（引号/双层引号/反斜杠/尾斜杠/相对/drive-relative/控制字符/UNC）、版本（None/1.x/17.0.9/21-ea/不可解析/≥10 位）、required_major（7/8/99/100）。
- 模板维度：app_name（空/65 字符/控制字符/五特殊字符）、module_deps（非法/重复）、assets（穿越/重复 target/坏哈希）、篡改树（非法根/重复路径/分隔符整行注入）。

## 4. L1 性质与变异

**变形律 P#**（W9 落地；标注现状）：

- P1 确定性律：`f(x)` 双次调用逐字节相等（plan_build/render_script/render_template_script/render_native_manifest/probe_jdk）。现状：render 双例在码（B17），其余 W9 补齐。
- P2 ABI 覆盖律：`plan_build(c, abis).config.abis == abis`（abis 非空时）；空时回落 `c.abis`。现状：在码。
- P3 attach 纯函数律：`attach_native_hashes(libs, hashes)` 不修改两个输入数组。现状：在码。
- P4 多重集合序不变律：`verify_artifact` 对 `artifact.abis`/`signatures` 的任意排列结果不变。现状：**缺口 → W9**。
- P5 ABI 往返律：`parse_abi_dir_name(abi_dir_name(a)) == a`，4 ABI 穷举。现状：**缺口 → W9**。
- P6 清单往返律：`render_native_manifest` 数据行数 == libs 长度，每行 `lib/<dir>/<soname>  sha256=<hex>` 与条目双射。现状：**缺口 → W9**。
- P7 **防火墙律**：任一 W# 合入后，旧函数全部既有用例**零改动全绿**、旧 API 在全部既有语料上输出逐字节不变（W2/W3 仅限书面裁决的 golden 行变化，且负例/错误路径用例仍零改动）。现状：作为每包 DoD 门禁，W9 固化为脚本断言。
- P8 模板一致律：`plan_template(p).build_plan == plan_build(p.config, [])`（步骤/输入/输出/生效配置逐字段）。现状：**缺口 → W9**。
- P9 heredoc 安全律：任一生成文件 content 含自身分隔符整行 → `InvalidTemplate`；不含时渲染文本中分隔符恰出现 2 次（开/闭）。现状：负例在码，计数断言 W9 补。
- P10 XML 转义律：`render_manifest`/`render_strings` 输出中，文本节点与属性值内无裸 `& < > " '`（实体除外）；app_name/entry_url 注入五字符必被转义。现状：五字符用例在码，全文扫描断言 W9 补。

**字符串位翻转/变异**（格式依赖口径）：本库输入多为自由字符串，翻转后可能仍是合法输入——断言口径为「**要么报声明的 14 变体之一，要么输出与翻转前不同**」，不得断言全部必错（防假绿）。哈希/版本号等规格字段例外：单字符破坏必被对应规格校验拒绝（`is_sha256_hex`/`jdk_major` fail-closed）。

**边界值矩阵**：min_sdk/target_sdk ∈ {−1, 0, 1, 23, 24, 33, 34, 100, 101}；app_name 长度 {0, 1, 64, 65}；sha256 长度 {63, 64, 65}；required_major {7, 8, 99, 100}；jdk_major 位数 {9, 10}；soname 长度 {6, 7}（`lib` + `.so` 最短合法 stem=1）。

**变异语料**：固定种子（seed=20261116）对路径/包名/版本号/哈希/soname 五类字符串做替换/插入/删除/截断，每轮 ≥1000 变异体；只允许声明错误类型或正常值输出，不允许 panic/挂起。落 wbtest（内部助手直测）+ 黑盒公开 API 双通道。

## 5. L3 oracle 矩阵 + R runner

| oracle | 差分对象 | 规范化口径 |
|---|---|---|
| 官方 apksigner 文档 flag 清单（静态） | 渲染 Apksigner 命令行每个 flag | 只比 flag 名与取值形态是否在官方清单内；不比签名结果（本库不签名） |
| 官方 aapt2/d8/zipalign 文档（静态） | 渲染命令行子命令/参数形态 | 同上；`zipalign -p -f 4` 顺序与官方一致 |
| 本机 apksigner/zipalign（动态，可选） | `--help` flag 面 | 本地装有 build-tools 时跑；缺失 → 显式 SKIPPED（退出码 78 口径），不得写成通过 |
| 本机 JDK（动态，可选） | probe_jdk 结论 vs `java -version` 实测 | 采集器属组合根；R runner 只做受控快照差分 |

纪律：oracle 缺失 → 显式 SKIPPED + 原因；oracle 版本随结果登记（build-tools 锁 34.0.0，B25）。静态 oracle 以 2026-11-16 抓取的官方文档为准，文档更新须重核（易变事实 [需联网核实]）。
R runner：样本路径 + 登记哈希 → 哈希不符拒绝执行 → 规范化差分 → 报告「本地已差分 + 哈希 + 日期」；入库 #skip 用例保留不删，真实结论永不进入通过计数。当前本库零真实样本依赖，R 层为设计保留。

## 6. 覆盖矩阵与错误簿记

### 6.1 能力×场景×安全 覆盖矩阵

现状列来自 P4 实测（B#）；✓=在码，△=部分，✗=缺口。

| ID | 能力/场景 | L0 | L1 | L2 | L3 | L4 | 现状（P4） | 缺口→W# |
|---|---|---|---|---|---|---|---|---|
| F1 | plan_build 规范 10 步/全序 | ✓ | △ | — | — | ✗ | 正例+负例在码；InvalidStepOrder 仅渲染入口可达（B4） | W1 措辞 / W9 P7 |
| F2 | render_script 确定性渲染 | ✓ | △ | ✓ | ✗ | ✗ | golden+双次一致（B17）；无 set -eu（B12） | W2 / W9 P1 |
| F3 | 密钥引用制四入口 | ✓ | ✗ | ✓ | — | ✗ | 10 处断言（B6/B16） | W9 变异 |
| F4 | 签名方案校验 | ✓ | ✗ | △ | ✗ | ✗ | 冲突矩阵在码；渲染伪 flag（B21） | W3 |
| F5 | 版本锁 7+1 | ✓ | ✗ | ✓ | — | ✗ | 逐字段负例在码（B5） | W9 边界 |
| F6 | 包名校验 | ✓ | △ | — | — | ✗ | 规则矩阵在码 | W9 变异 |
| F7 | ABI 名/反解/基线 | ✓ | ✗ | — | — | ✗ | 正反例在码；往返律缺 | W9 P5 |
| F8 | verify_artifact | ✓ | ✗ | — | — | ✗ | 6 例在码；序不变律缺（B8） | W9 P4 / W1 措辞 |
| F9 | ci_gate_plan | ✓ | ✗ | — | — | ✗ | 顺序断言在码（B23） | — |
| F10 | plan_template 6 文件 | ✓ | △ | ✓ | — | ✗ | 内容映射+转义在码；一致律缺 | W9 P8/P10 |
| F11 | render_template_script 四阶段 | ✓ | △ | ✓ | ✗ | ✗ | golden+篡改负例在码；fail-open（B12） | W2 / W9 P9 |
| F12 | .so 清单 fail-closed | ✓ | ✗ | — | — | ✗ | 未登记拒绝在码；往返律缺 | W9 P6 |
| F13 | 资产注入校验 | ✓ | △ | ✓ | — | ✗ | 穿越/重复/坏哈希在码 | W2 阻断 / W9 变异 |
| F14 | probe_jdk | ✓ | △ | — | △ | ✗ | 11+2 例矩阵；溢出缺口（B19）；严格模式缺（B18） | W6 / W7 / W9 边界 |
| F15 | BuildPlanner trait | ✓ | — | — | — | — | wbtest 兑现在码；README 漏列（B1） | W1 |
| F16 | 错误模型 14 变体 | ✓ | — | — | — | — | 14/14 显式断言；MissingGate 死变体（B9/B16） | W1 声明 |
| S1 | 计划→渲染→校验 全链 | △ | ✗ | △ | ✗ | ✗ | 各段独立在码，无串联用例 | W9 |
| S2 | 模板→脚本 全链 | △ | ✗ | ✓ | ✗ | ✗ | golden 覆盖单 ABI；双 ABI+资产串联缺 | W9 |
| S3 | 清单→回填→校验→渲染 全链 | △ | ✗ | — | — | ✗ | 各段在码，串联缺 | W9（W5 互操作） |
| S4 | JDK 采集快照→评估→诊断 | ✓ | ✗ | — | △ | ✗ | 受控快照在码；真实 oracle 可选 | W9 / R |
| C1 | 密钥零嵌入/零泄漏 | ✓ | ✗ | ✓ | — | ✗ | 四入口+渲染泄漏断言在码 | W9 变异自检 |
| C2 | 穿越/注入拒绝 | ✓ | △ | ✓ | — | ✗ | heredoc/路径/soname 负例在码 | W9 变异 |
| C3 | 未登记 fail-closed | ✓ | ✗ | — | — | ✗ | 清单/渲染拒绝在码 | W9 恒等式 |
| C4 | 脚本失败阻断语义 | ✗ | ✗ | ✗ | ✗ | ✗ | **fail-open（B12）** | W2 |
| C5 | 防火墙（新函数不改旧语义） | △ | ✗ | △ | — | ✗ | 靠 DoD 人工执行，未脚本化 | W9 P7 |
| C6 | 许可红线（F-D 零入库） | ✓ | — | — | — | — | 零文件 fixture、零二进制（B15） | W9 ref-scan |
| C7 | CLI flag 保真（官方工具面） | ✗ | ✗ | ✗ | ✗ | ✗ | **伪 flag（B21）** | W3 |

### 6.2 错误变体触发簿记（14/14 强制）

| 变体 | 触发 fixture（现状，显式断言变体名） | 新增触发（待建） |
|---|---|---|
| InvalidPackage | 非法包名矩阵（moon_android_test L180） | W9 变异语料 |
| UnsupportedAbi | 空/重复 ABI、非法目录名（L373；native_abi_test L32/L93） | W9 P5 负例 |
| MissingTool | cmake 缺失、渲染缺工具（L267/L533） | — |
| ToolchainNotLocked | 逐字段置空（L231） | W9 边界 |
| InvalidStepOrder | 手造乱序计划经 render_script（L518）；wbtest 直测 | W9 P7 篡改 |
| KeyMaterialEmbedded | 六类信号×四入口（L291/L566；template_test L640） | W9 变异 |
| SigningSchemeConflict | 空/重复/缺 V1/缺 V3（L342） | W3 后重验 |
| ArtifactMismatch | 路径/空产物/坏哈希/空集合/缺 Apksigner（L624-714） | W9 P4 |
| MissingGate | **仅 wbtest 人工 raise（L253）；库内零触发点（B9）** | 不新增（保留变体，W1 声明） |
| MissingAbi | 缺哈希/缺 required ABI（native_abi_test L130/L184） | W5 互操作 |
| InvalidNativeLib | 坏 soname/目录漂移/坏哈希/未登记（L51/L147/L184/L264） | W5 重复 soname |
| InvalidAsset | 穿越/坏哈希/重复 target（template_test L223） | W9 变异 |
| InvalidTemplate | 坏 app_name/坏 deps/篡改树/分隔符注入（L170/L195/L569） | W9 P9 |
| InvalidJdkProbe | required_major 越界（jdk_test L187） | W6/W7 边界 |

门禁：每变体 ≥1 显式断言变体名的用例；`MissingGate` 的 whitebox 人工触发**单独标注**，不计入「生产触发」口径（防死变体假绿）。

### 6.3 恒等式断言（语义契约，全路径成立）

- `plan_build` 输出步骤恒等于 `canonical_steps()`（10 步、秩严格递增）；`inputs.length == outputs.length == steps.length`。
- `render_native_manifest` 成功 ⇒ 全部条目 `sha256 is Some` 且 64 位 hex（未登记 ≠ 通过）。
- `attach_native_hashes` 成功 ⇒ 输出每条目 sha256 已登记且输入数组不变。
- `verify_artifact == true` ⇒ path 与计划 Apksigner 产物名相等 ∧ ABI/签名多重集合相等 ∧ size>0 ∧ sha256 规格合法。
- `probe_jdk.status == JdkFound` ⇒ `selected is Some` ∧ selected 目录在 existing 集合 ∧（version=None ∨ 主版本匹配）；strict 模式（W7）下 version=None 分支恒不选中。
- 渲染文本恒含 `DO NOT EXECUTE` 头 ∧ 不含 keystore 口令信号（六类）；W2 后恒含 `set -eu`。
- `plan_template(p).build_plan == plan_build(p.config, [])`（P8）。
- **防火墙恒等式**：任一 W# 合入后旧函数全部既有用例零改动全绿（W2/W3 书面裁决 golden 行除外）。

### 6.4 #skip 清单（显式单列，永不计入通过）

| 用例 | 位置 | 原因 |
|---|---|---|
| （无） | — | 当前基线零 #skip（2026-11-16 实测 grep 零命中） |

计数口径：79 条声明 − 0 条 #skip = 79 执行，79 通过（wasm 与 native 各一次，2026-11-16）；`--include-skipped` 结果与常规一致（无 skip）。未来 L3/R 层 SKIPPED 用例一律单列本表，退出码 78 口径，不得写成通过。

### 6.5 验收 ID 双向追溯表

| T-W*-* | W#（开发文档） | 矩阵缺口行 | 断言/层 |
|---|---|---|---|
| T-W1-1 引用实存性扫描零悬空（注释/ci.yml/脚本） | W1 | F1/F15/F16 措辞、B13 | A5/L5 |
| T-W1-2 README 索引 ↔ mbti 逐条一致（含 trait） | W1 | F15 | A5/L5 |
| T-W1-3 五门禁绿 + mbti 零 diff | W1 | C5 | A5/L5 |
| T-W1-4 CHANGELOG 实存且登记本轮 | W1 | — | A5/L5 |
| T-W2-1 render_script 含 set -eu（shebang 后首行） | W2 | C4/F2 | A2/L0+L2 |
| T-W2-2 render_template_script 含 set -eu | W2 | C4/F11 | A2/L0+L2 |
| T-W2-3 golden 重录 diff 仅限预期行 + 书面裁决记录 | W2 | C4 | A5/L2 |
| T-W2-4 旧错误路径用例零改动全绿 | W2 | C5 | A5/L5 |
| T-W2-5 资产阶段校验行先于复制行且阻断语义成立 | W2 | C4/F13 | A2/L0 |
| T-W2-6 mbti 零 diff（无 API 变化） | W2 | C5 | A5/L5 |
| T-W3-1 渲染命令不含 --v31-signing-enabled | W3 | C7/F4 | A1/L0 |
| T-W3-2 V31 渲染为官方 flag 组合 + 轮换注释 | W3 | C7 | A1/L0+L3 |
| T-W3-3 --min-sdk-version/--max-sdk-version 与 config 一致 | W3 | C7 | A1/L0 |
| T-W3-4 golden 重录书面裁决 + CHANGELOG | W3 | C7 | A5/L2 |
| T-W3-5 旧负例零改动全绿 | W3 | C5 | A5/L5 |
| T-W3-6 官方 flag 清单静态 oracle 比对（本机动态可选 SKIPPED） | W3 | C7 | A1/L3 |
| T-W4-1 check_sdk_range 边界矩阵（−1/0/1/23/24/100/101/min>target） | W4 | F1/B11 | A4/L0+L1 |
| T-W4-2 check_entry_url 矩阵（WebView 缺/坏 scheme/http/https/file/其他壳） | W4 | F10/B11 | A4/L0 |
| T-W4-3 旧 plan_build 同语料行为不变（防火墙） | W4 | C5 | A5/L5 |
| T-W4-4 快照 diff 纯加法（2 struct + 2 fn） | W4 | C5 | A5/L5 |
| T-W5-1 plan_extra_native_libs 双 ABI 布局 + sha256=None | W5 | F12/B10 | A3/L0 |
| T-W5-2 坏 soname/重复 → InvalidNativeLib；空 ABI → UnsupportedAbi | W5 | F12 | A2/L0 |
| T-W5-3 与 attach/validate/render 互操作全链 | W5 | S3 | A2/L0 |
| T-W5-4 旧 API 零改动（plan_build 不消费该字段） | W5 | C5 | A5/L5 |
| T-W5-5 快照 diff 纯加法（1 fn） | W5 | C5 | A5/L5 |
| T-W6-1 ≥10 位版本 → 不可解析 → JdkVersionUnmatched（无伪匹配） | W6 | F14/B19 | A4/L1 |
| T-W6-2 9 位边界正常解析 | W6 | F14 | A4/L1 |
| T-W6-3 正常语料 probe_jdk 输出逐字不变 | W6 | C5 | A5/L5 |
| T-W6-4 CHANGELOG fail-closed 登记 | W6 | C5 | A5/L5 |
| T-W7-1 strict 下 version=None → 不选中 + 诊断 | W7 | F14/B18 | A2/L0 |
| T-W7-2 版本齐备语料 strict 与非 strict 结论一致 | W7 | F14 | A5/L1 |
| T-W7-3 旧 probe_jdk 零改动 | W7 | C5 | A5/L5 |
| T-W7-4 快照 diff 纯加法（1 fn） | W7 | C5 | A5/L5 |
| T-W8-1 gates 子命令 7 行输出 + 退出码 0 | W8 | F9/B14 | A5/L4 |
| T-W8-2 render 正例退出码 0 + DO NOT EXECUTE 头 | W8 | S1 | A1/L4 |
| T-W8-3 非法包名退出码 1 + stderr 变体名 | W8 | F6 | A5/L4 |
| T-W8-4 用法错误退出码 2 | W8 | B14 | A5/L4 |
| T-W8-5 密钥内嵌退出码 1 且 stdout 无密钥材料 | W8 | C1 | A3/L4 |
| T-W8-6 库 mbti 零 diff（CLI 不改库面） | W8 | C5 | A5/L5 |
| T-W9-1 变形律 P1–P10 套件全绿 | W9 | P4/P5/P6/P8/P9/P10 缺口 | A1/A2/L1 |
| T-W9-2 变异自检：3 类缺陷注入必须变红后还原复绿 | W9 | C5 | A5/L5 |
| T-W9-3 双目标 parity 脚本 diff=0 | W9 | A6 | A6/L5 |
| T-W9-4 错误簿记门禁 14/14（MissingGate 单列口径） | W9 | F16 | A2/L5 |
| T-W9-5 ≥1000 变异体无 panic/挂起，仅声明错误类型 | W9 | C2/A4 | A4/L1 |

## 7. L4 CLI 场景 E2E（W8 裁决选 A 后生效）

| 场景 | 命令序列 | 断言要点（退出码+输出） |
|---|---|---|
| 门禁清单 | `moon run cmd/main -- gates` | 退出码 0；stdout 恰 7 行、顺序 FmtCheck→…→VersionLock |
| 渲染正例 | `moon run cmd/main -- render --package com.example.app --abis arm64-v8a --min-sdk 24 --target-sdk 34 --schemes V2,V3 --keystore-ref @keys/release.jks` | 退出码 0；首行 `#!/bin/sh`；含 DO NOT EXECUTE；不含密钥信号 |
| 校验拒绝 | 同上但 `--package bad` | 退出码 1；stderr 含 `InvalidPackage`；stdout 无渲染文本 |
| 用法错误 | `moon run cmd/main -- nonsense` | 退出码 2；stderr 用法提示 |
| 密钥拒绝 | `--keystore-ref "password=abc"` | 退出码 1；stderr 含 `KeyMaterialEmbedded`；stdout 全文无 `password=abc` |
| JDK 探测 | `moon run cmd/main -- probe-jdk --java-home "C:\jdk17" --required-major 17 --existing "C:\jdk17"` | 退出码 0；stdout 含 JdkFound |

记录行/JSON 契约冻结口径：本库当前无 CLI 记录行契约（B14）；W8 落地时 stdout 渲染文本以 golden 冻结、gates 输出以 7 行常量冻结，变更即破坏。退出码矩阵 **0/1/2** 逐例断言；失败路径退出码**实跑**（防 fail-open 退出码 0 先例）。

## 8. L5 元契约门禁

1. **快照门禁**：`moon info` + `git diff --exit-code -- pkg.generated.mbti cmd/main/pkg.generated.mbti`（ci.yml 已在码）；加法包 diff 必须纯加法。
2. **双目标等价**：`tools/parity.sh`（W9）——wasm/native 各跑 `moon test` 并比对渲染类用例输出逐字节 diff=0；现状手工双跑已验证 79/79×2（B2）。
3. **错误簿记门禁**：§6.2 与测试代码双向核对（grep 变体名），缺一即红；MissingGate 人工触发单列。
4. **变异自检**：`tools/mutation-selfcheck.sh`（W9）注入 3 类缺陷——①跳过 `validate_native_manifest` 哈希检查 ②放行 `looks_like_key_material` 恒 false ③篡改 `step_rank` 使 Zipalign>Apksigner——套件必须变红后还原复绿。
5. **计数纪律**：#skip 不计通过；测试过滤串以 `*` 结尾防空转假绿；一切计数以实跑为准。
6. **引用实存性扫描**：`tools/ref-scan.sh`（W9）——注释/帮助文本/ci.yml/脚本引用的仓库内路径全部实存；README API 索引与快照逐条一致（含 pub trait）；兄弟模块文件引用/工作区路径零命中。

## 9. CI 集成与执行入口

五门禁不变（ci.yml 在码，wasm 后端）；L0/L1/L2 挂 `moon test`；L3/L4/R/parity/mutation 为脚本层可选 job，缺失显式 SKIPPED。
复验命令（本仓库自包含）：

```sh
moon clean
moon check --deny-warn
moon build
moon test
moon fmt --check
moon info
git diff --exit-code -- pkg.generated.mbti cmd/main/pkg.generated.mbti
# 可选加固层（W9 落地后）：
sh tools/parity.sh
sh tools/mutation-selfcheck.sh
sh tools/ref-scan.sh
```

## 10. 维护规则与验收清单

1. 新增 pub API ⇒ 同提交附 L0 样例 + L1 性质 + 矩阵/簿记更新；无测试不合入。
2. 新增字符串解析路径 ⇒ 进变异语料 fixture 集（五类字符串 builder）。
3. golden 变更 ⇒ 仅限书面裁决的缺陷修复（W2/W3），CHANGELOG + 回归 diff 同提交。
4. 每包合入 ⇒ 开发文档 DoD 勾选 + 矩阵现状刷新 + CHANGELOG 测试增量。
5. 「通过」须可复验：命令 + 日期 + 计数；SKIPPED 永远单列。

落地验收（逐层勾选）：
- [ ] L0：79 例基线保持全绿（每包合入后重测计数）
- [ ] L1：P1–P10 全绿 + ≥1000 变异体扫描零 panic（W9）
- [ ] L2：两处 golden 与源码一致；重录须书面裁决（W2/W3）
- [ ] L3：静态 oracle 比对在码；动态 oracle 缺失显式 SKIPPED（W3/W9）
- [ ] L4：退出码矩阵 0/1/2 逐例实跑（W8 裁决选 A 后；未裁决前本行保持「未实现」）
- [ ] L5：六道元门禁脚本化并挂 CI 可选 job（W9）
- [ ] R：设计保留，当前零样本；真实样本永不入库