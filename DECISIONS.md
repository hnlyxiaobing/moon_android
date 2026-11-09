# moon_android · 设计决策记录（DECISIONS.md）

> 本文整合本项目开发期的决策记录（背景 → 决策 → 理由 → 后果），内容自足：社区开发者只需本仓库内的文件即可理解全部取舍依据。各条均源自开发期决策记录，已按本仓库口径改写；本文不引用仓库外的任何文件。

## 决策 1 · 定位：只做「计划 / 配置」层，产出 BuildPlan、脚本文本与校验，不执行命令、不产 APK

**背景**：`moon build --target` 只有 wasm / wasm-gc / js / native / llvm / all，**没有 android 目标**；官方「一门语言、多后端」未把 Android 集成列入目标；native 后端的 `foreign_library` 不能导出可链接的 `.so/.dll`。社区现状只有 JNI 桥接件与一个 legacy 模板，没有「一条命令出 APK」的现成方案。可行通路是「C stub + 宿主 NDK/CMake + aapt2 / d8 / zipalign / apksigner」的外围工具链。

**决策**：`moon_android` 只做 APK 打包链的「计划与配置」契约——由 `BuildConfig` 生成有序 `BuildPlan`（含步骤顺序校验）、渲染可审阅的脚本文本、校验产物元数据（size / sha256 / ABI / 签名方案）、给出建议的 CI 门禁序列；R4 增补**模板生成树**、**双 ABI `.so` 清单**与 **JDK 纯评估器**。**不执行任何外部命令、不签名、不调 adb、不读写 APK、不实现 Gradle / IDE 集成、不管理密钥材料、不读环境变量或注册表（JDK 采集器属组合根）、不下载 SDK。**

**理由**：

- **zipalign 必须先于 apksigner**：官方口径是「签名后任何改动都会使签名失效」，因此 `BuildStep::Zipalign` 排在 `BuildStep::Apksigner` 之前是**硬约束**（10 步计划：`CrossCompile → Aapt2Compile → Aapt2Link → Javac → D8 → Assemble → Zipalign → Apksigner → Verify → AdbInstall`），违规计划由 `InvalidStepOrder` 拒绝。
- **密钥引用制**：`keystore_ref : String` 只存**引用**，禁止内嵌密钥材料；`MoonAndroidError::KeyMaterialEmbedded` 是可观察的拒绝信号，`plan_build` 与 `render_script` 均主动返回而不是静默降级。签名密钥不入库。
- **只分发文本**：Android SDK License Agreement 3.4 禁止复制 / 修改 / 再分发 build-tools 与 NDK 二进制（备份除外），因此本仓库**只分发计划与配置文本**，不打包、不分发任何 SDK/NDK 工具二进制；aapt2 / d8 / zipalign / apksigner 只以命令行模板文本（`render_script` 产出，可审阅、不执行）出现。
- 签名方案约束随配置校验强制执行：`min_sdk < 24` 必须启用 V1（低版本设备无法校验 v2+ 签名）；V31（密钥轮换）必须与 V3 同启。

**后果**：本库为纯 MoonBit 值类型 + 纯函数（无句柄、无 I/O、无 FFI、无外部句柄），全后端、桌面可测；命令执行、签名、adb、APK 读写留给未来的组合根 / 脚本执行层。计划与配置可以先行验证，不受设备与 SDK 到位时间影响。

**R4 补记（2026-11-09，只补事实、不改结论）**：模板泛化、双 ABI 清单与 JDK **纯评估器**已落地；它们仍全部是纯值/纯函数，未引入进程、文件、环境或注册表访问。JDK 探测的边界按「采集器在组合根 / 评估器在库内」执行（决策 7），因此「本库不探测 JDK」的原意（不做 I/O 探测）不变。

## 决策 2 · 模板泛化先验证再抽象（R4 已落地纯值模板；设备通路仍待实测）

**背景**：最初的骨架定位是「先解决能出包」——首个交付物即参数化脚本模板（`moon android build --abi …` 一类）+ WebView/GLES 双壳 Activity + 双 ABI so 管理，并把 NDK 交叉编译当作硬前置。

**决策**：把「一次性脚本泛化为可配置模板」**后移**（本仓库当前只提供命令模板文本；模板泛化属后续阶段）。设备端通路验证（从 `moon build` 到目标设备应用启动一条命令）先用**一次性 shell APK 脚本**完成；该脚本是临时验证物、不是交付物。本仓库的「计划 / 配置」部分先行（桌面可测）。

**理由**：「先验证再抽象」。若 Android native 产物链路（MoonBit → C 源码/对象 → NDK clang + CMake → 可加载 `.so`）尚未跑通就泛化模板，会把未验证的假设固化成接口，返工成本高；一次性脚本是**更小替代方案**，足以证明「MoonBit 产物能在目标设备启动」。同时把 NDK 交叉编译从硬前置**降级为上板软依赖**——C API `.so` 与插桩 devkit 都是预编译产物，桌面验证不需要 NDK。

**被替代方案**：直接做参数化模板 + WebView/GLES 双壳 Activity + 双 ABI so 管理。风险：若 native 产物链路未跑通，模板全部作废。

**后果**：FFI 相关工作可与打包链并行推进，不再被打包链阻塞；上板时仍**必须**补齐 `moon_abi` 配置，不能省略；一次性脚本必须明确标注为临时验证物。若后续证明通路由一次性脚本更合适，可直接替换 `render_script` 输出的消费方式，不改上层调用（`BuildPlan` 不含可执行动作，天然可替换）。

### R4 修订补记（2026-11-09）：模板泛化已落地，但「先验证再抽象」原则不变

- **事实**：R4 已实现 `plan_template`（`TemplateParams` → `GeneratedTree`）与 `render_template_script`（四阶段脚本），把参数化（包名/应用名/ABI/模块依赖/资产注入）固化为可测试接口；映射见 `TEMPLATE.md`。
- **不推翻**：ADR-0005 O6 的排序（先一次性脚本证明 A4、再泛化）与决策 2 的「先验证再抽象」**原则不变**。本轮泛化的是**已被计划层验证的纯值接口**（10 步顺序、版本锁、签名约束、路径规则），**不是**设备端通路结论：E3（NDK clang + CMake 产出可加载 `.so`）与 Q1（一条命令到设备启动）仍未实测，`[仍需实测]`。
- **风险留痕**：若设备端通路最终证明模板形状不适用，`GeneratedTree`/脚本渲染是纯值可替换层，改动局限在 `template.mbt` 与文档，不触碰已冻结的 `BuildPlan` / `render_script` 签名。
- **执行链**：本机环境（JAVA_HOME 失效、build-tools/platform/JDK 与锁不符、NDK/CMake 缺失）导致按锁定版本不可执行，详见 `EXECUTION-CHAIN.md` §3；该结论**不**被模板泛化掩盖。

## 决策 3 · 跨模块只以文本片段协作，用名义类型隔离消解潜在循环依赖

**背景**：MoonBit 是**名义类型系统**，两个模块里结构完全相同的 `struct` 也不是同一类型。若把「解析 → 打包」链条实现成编译期 import（打包层依赖解析产物类型、解析层又依赖打包配置），会产生**潜在循环依赖**，并把某个模块变成中心节点。

**决策**：

- 本库与 `moon_abi` 只以**配置片段文本**协作：`moon_abi` 只输出配置文本、不读打包产物；文本由组合根（未来 App 工程里的一段适配代码）写入目标 App 的 `moon.pkg`。**不 import、不传递 `LinkNativeConfig` 一类结构化类型**。
- `Abi` 等跨模块值类型**同构但独立**定义（各模块自带一份），由组合根做转换；`#external` 句柄、JNIEnv、`FuncRef` 永不跨模块传递。

**理由**：文本契约 + 名义类型隔离把依赖方向收敛为**单向数据流**，从结构上消解潜在循环依赖；各模块可独立 `moon check`、并行开发；API 边界被迫写成中性值类型，天然满足「后端可替换、实现细节不泄漏」。

**后果**：组合根需要少量显式适配代码；同构类型存在结构漂移风险，靠 `pkg.generated.mbti` API 快照对账与契约测试守住。

## 决策 4 · 解析库不承担打包

**背景**：解析层（APK 容器 / AXML / DEX）如果承担打包或签名职责，容器层 API 会被下游解析类型与打包状态绑架，接口随下游格式演进而被迫变更。

**决策**：解析库只做「ZIP 中央目录 + Android 专有结构索引」，只产出原始字节与索引（如 `ManifestRef.raw` / `DexEntry.bytes`），不打包、不签名、不返回下游解析类型。签名在本库只作为 `BuildStep::Apksigner` **计划项**出现，且不执行。

**理由**：职责分离让容器层接口不随下游格式演进；审计 / 清单类使用者可以只依赖解析层；本库保持零 import、不解析 APK。

**后果**：「先解析 manifest 还是先扫描 dex」由组合根决定；签名识别结果明确标注 `verified = false`，不会被误当作已验签。

## 决策 5 · 版本锁强制；`--deny-warn` 门禁在实现完成后恢复

**背景**：MoonBit 工具链无 LTS 承诺、约每月一版且多处 `[breaking]`，版本漂移会让构建不可复现。声明阶段大量 `declare` 占位会产生 `[0068] declaration_unimplemented` 告警，而 `moon check --deny-warn` 会把它们升级为 error。

**决策**：

- **版本锁强制**：`ToolchainVersions` 的 **7 个必填字段**（`moon_cli` / `moonc` / `core` / `ndk` / `build_tools` / `platform` / `jdk`；另有可选 `cmake`）**缺任一即视为未锁定**，`plan_build` 拒绝（`ToolchainNotLocked`），CI 必须拒绝未锁定配置。测试夹具与快照锁定 `moon 0.1.20261104` / `moonc v0.10.20+65efd5b93`；CI 对安装结果做版本断言，漂移即失败。
- **`--deny-warn` 门禁口径变化**：早期实现未完成阶段（存在 65 条 `[0068] declaration_unimplemented` 占位告警时）曾**临时豁免** `--deny-warn`、以普通 `moon check` 作最低门槛，并把 `0068` 视为「待实现清单」；实现完成后 `0068` 归零，**豁免随之失效**——四道门禁统一为 `moon check --deny-warn` / `moon build` / `moon test` / `moon fmt --check`（开发期同批 11 个模块拒警告全部通过，本库 0 条 `0068`）。CI 另设「`0068` 计数单调不增」软检查，防止用伪实现消警告而不写实现。

**理由**：版本锁让构建可复现、可审计，「任一为空即拒绝」避免半锁定状态混入 CI；`0068` 豁免只是声明阶段的临时口径，其恢复条件（实现完成、`0068` 归零）是客观可判的，一旦达成就恢复最严门禁。

**后果**：`Gate::CheckDenyWarn` 是 7 项建议门禁之一（固定顺序 `FmtCheck → Check → CheckDenyWarn → TestCoverage → Bench → InfoSnapshot → VersionLock`）；升级工具链须按实测版本更新锁值并重跑快照；`pkg.generated.mbti` API 快照保留在版本库中作为评审依据。

## 决策 6 · `create-moonbit-raylib-android-app` 只作参照，不作依赖；当前零依赖

**背景**：APK 打包链无现成可用方案；唯一沾边的 `create-moonbit-raylib-android-app@0.1.0` 是 **legacy 模板**（仍带 `moon.pkg.json`；普通工具链命令已不再接受 JSON manifest），直接依赖会失败。候选复用件（JNI 绑定、ZIP 解压等）均为 0.x 或有平台 / 许可限制。

**决策**：纯 MoonBit 自研「计划 + 配置」；`create-moonbit-raylib-android-app` **只作设计参照、不可直接依赖**。当前**零新增依赖**：不 `moon add`、不改 `moon.pkg`、无 FFI、无外部句柄。后续新增依赖须**同时**过五条门槛并留痕：**用途**（现有能力无法以更小代价覆盖）、**许可**（SPDX 已核验、与 Apache-2.0 兼容）、**维护**（版本 / owner / 更新状态 / 是否 legacy）、**平台**（目标后端一致、不破坏独立 `moon check`）、**风险**（登记替代方案与移除成本）。

**理由**：legacy 包直接依赖会因 JSON manifest 被拒；任何依赖都会引入网络 / 版本耦合并破坏「可独立 `moon check`」的性质；计划/配置层不需要任何依赖即可完成。SDK License 3.4 也禁止再分发 SDK/NDK 二进制（见决策 1），进一步压缩了可依赖面。

**后果**：仓库无依赖叠加风险，评审范围收敛到本仓库内的文档与声明；后续若引入解析类依赖（如 ZIP 解压），按五门槛审计留痕后再引入，移除成本被限定在单个模块内。

## 决策 7 · R4 三项边界：模板纯值、双 ABI fail-closed、JDK 采集/评估分离

**背景**：R4 要落地模板泛化（ADR-0005 O6）、双 ABI `.so` 管理与 Windows JDK 探测。三者都天然接近「执行 / 文件 / 环境」；若处理不当会把 I/O、工具二进制或平台细节带进本库，破坏零依赖、全后端可测与 API 快照确定性。

**决策**：

1. **模板只产出纯值 + 文本**：`plan_template` 返回 `GeneratedTree`（`GeneratedFile.path/content` 等纯值），`render_template_script` 只渲染四阶段脚本文本；不建目录、不写文件、不复制资产、不执行 `sha256sum`。资产与 `.so` 内容**不入库、不进库**，只登记路径 + SHA-256。
2. **双 ABI fail-closed**：`NativeLib.sha256 = None` 是「未登记」而非通过；`render_native_manifest` 拒绝未登记清单；`validate_native_manifest(libs, dual_abi_set())` 缺任一 ABI 即 `MissingAbi`；目录与 ABI 不一致、重复 ABI、非法 soname 均拒绝。ABI 集顺序按输入保留，不隐式重排。
3. **JDK 采集/评估分离**：库内 `probe_jdk` 只吃组合根给的 `JdkProbeEnv` 快照（`JAVA_HOME` / 注册表项 / 常见路径 / PATH / 已验证目录 / 要求主版本），做排序、去重、存在性、版本匹配；I/O 采集属于组合根。候选路径非法只记诊断并跳过，`required_major` 非法才 `InvalidJdkProbe`。

**理由**：

- 纯值边界保证 `moon test` 可在 wasm 后端、无 SDK/JDK 的 CI 上全绿，API 快照不引入平台差异；执行链风险可以用**受控输入**单元测试覆盖（本机实测的失效 `JAVA_HOME`、JDK 21/1.8 并存、注册表键位都能构造为 `JdkProbeEnv`）。
- fail-closed 避免「未登记 = 通过」的假通过：`.so` 哈希缺失、ABI 缺失必须在清单/校验阶段被拒绝，而不是留到设备安装时失败。
- 采集/评估分离让 Windows 专有 I/O（注册表、引号、盘符）留在组合根，库保持跨后端；同时给组合根明确的契约与诊断。

**后果**：R4 新增 13 个公开类型、10 个公开函数、5 个错误构造，全部为加法性（既有签名冻结）；执行链的宿主差异被隔离在组合根，库侧风险登记于 `EXECUTION-CHAIN.md`。若将来要支持非 Windows 主机的注册表等价物（Linux alternatives / macOS `/usr/libexec/java_home`），只需扩展采集器，评估器不变。

**被替代方案**：① 让库直接读环境变量/注册表（否决：wasm 后端不可用、破坏确定性与快照门禁、引入平台条件编译）；② 模板直接写文件（否决：违反「不执行、不 I/O」与红线 2 的资产不入库）；③ 哈希缺失时按「未登记」放行（否决：假通过，违反 fail-closed 与 ADR-0011 的同类口径）。

## 附 · 声明策略：具体类型用真实定义

`declare` 只支持函数签名、抽象类型与实现关系，不能声明 `struct` / `enum` / `trait` / `suberror` / type alias（编译器报「Cannot declare a type with concrete definition」）。因此具体数据类型（R4 后共 **24 个值类型**、`BuildPlanner` trait、`MoonAndroidError` 的 **14 个错误构造**）一律用**真实类型定义**——只有类型形状、无业务逻辑；**14 个公开函数**为**真实实现**（0 条 `0068`，无 `declare` 占位）。公开 API 带 `///` 文档注释；`pkg.generated.mbti` 快照与源码对账一致，**冻结后签名变更即破坏性变更**（R4 全部为加法性新增，既有签名未改）。
