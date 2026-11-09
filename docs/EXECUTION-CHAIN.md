# 执行链落地评估与 Windows JDK 探测（EXECUTION-CHAIN.md）

> 状态：**R4 评估完成**（2026-11-09）｜ 范围：aapt2 / d8 / zipalign / apksigner 执行链、双 ABI 注入、Windows JDK 探测
> 结论先行：**计划层与脚本文本层已落地并可测试；本机执行层未跑通（环境缺口，非代码缺陷）；设备层未测（Q1/E3）**。所有未实测项在本文标注 `[仍需实测]`，不写成通过。
> 证据等级：`[已复验]` = 本机命令/文件实测（2026-11-09）｜ `[已复验-本地等价]` = 同序命令本地等价实跑，非 GitHub Actions｜`[仅据文档]` = 只来自官方/仓库文档｜`[仍需实测]` = 无证据，不得当作通过。

## 1. 分层结论

| 层 | 内容 | 状态 | 证据 |
|---|---|---|---|
| A. 计划层 | `plan_build` 规范 10 步、Zipalign < Apksigner、版本锁、签名方案、ABI 校验 | ✅ 已落地 | 39 项既有测试；`[已复验]` |
| B. 脚本文本层 | `render_script`（既有）+ `render_template_script`（R4 四阶段、目录树物化、资产 SHA-256 校验） | ✅ 已落地 | 79 项测试；`[已复验]` |
| C. 本机执行层 | 真实 aapt2 / d8 / zipalign / apksigner 执行、CMake/NDK 编译 | ❌ **未跑通** | §3 实测：JAVA_HOME 失效、CMake/NDK 缺失、版本与锁不符；`[已复验]` |
| D. 设备层 | adb install + 应用启动（红米电视 / Android 9 / armeabi-v7a） | ❌ 未测 | Q1/E3；`[仍需实测]` |
| E. JDK 探测 | 纯评估器（优先级/去重/存在性/主版本） | ✅ 已落地；真实采集器属组合根 | 13 项测试；`[已复验]` |

## 2. 库侧已落地（R4）

- 模板：`plan_template` / `render_template_script`（映射见 `TEMPLATE.md`）。
- 双 ABI：`plan_native_libs` / `parse_abi_dir_name` / `attach_native_hashes` / `validate_native_manifest` / `render_native_manifest`。
- JDK：`probe_jdk`（纯评估器）。
- 边界不变：不执行命令、不签名、不调 adb、不读写文件、不读环境变量与注册表（零 import、零 I/O）。

## 3. 本机执行环境实测（2026-11-09）

### 3.1 关键发现：`JAVA_HOME` 失效直接阻断 d8 / apksigner

```text
> $env:JAVA_HOME
C:\Users\hnlyh\.jdks\corretto-19.0.2        # 该目录不存在（Test-Path = False）
> where javac
C:\Program Files\Common Files\Oracle\Java\javapath\javac.exe
> javac -version
javac 21.0.9

> apksigner.bat --version
ERROR: JAVA_HOME is set to an invalid directory: C:\Users\hnlyh\.jdks\corretto-19.0.2
exit 1

> d8.bat --version
ERROR: JAVA_HOME is set to an invalid directory: C:\Users\hnlyh\.jdks\corretto-19.0.2
exit 1

> $env:JAVA_HOME='C:\Program Files\Java\jdk-21'   # 受控修复后
> apksigner.bat --version
0.9                                                # exit 0
> d8.bat --version
D8 8.6.2-dev (...)                                 # exit 0
```

**结论**：JDK 探测不能只看 `JAVA_HOME` 是否存在字符串，必须验证目录存在且含 `bin/javac`；Windows 上 `JAVA_HOME` 与 `PATH` 的 javac 可能指向不同 JDK（本机：环境变量 = 19 且失效，PATH = 21）。这与 `probe_jdk` 的「存在性 + 主版本匹配 + 来源优先级」设计一致。

### 3.2 已安装组件（实测）

| 组件 | 实际值 | 命令/位置 | 证据 |
|---|---|---|---|
| Android SDK | `D:\Android\Sdk`（`ANDROID_HOME` / `ANDROID_SDK_ROOT` 均指向） | 环境变量 + 目录 | `[已复验]` |
| build-tools | **仅 `35.0.0`**（含 aapt2 2.19-11948202、zipalign、d8.bat、apksigner.bat、apksigner.jar） | `D:\Android\Sdk\build-tools\35.0.0` | `[已复验]` |
| platform | **仅 `android-35`**（`android.jar` 27,092,450 B） | `D:\Android\Sdk\platforms\android-35` | `[已复验]` |
| adb | `Android Debug Bridge version 1.0.41` / `37.0.1-15733141` | `D:\Android\Sdk\platform-tools\adb.exe` | `[已复验]` |
| NDK | **缺失**（`D:\Android\Sdk\ndk` 不存在） | `Test-Path` = False | `[已复验]` |
| CMake | **不在 PATH**（`where cmake` exit 1）；`C:\Program Files\CMake\bin\cmake.exe` 不存在 | `where cmake` | `[已复验]`（VS 自带 cmake 是否可用：`[仍需实测]`） |
| JDK（注册表） | `HKLM\SOFTWARE\JavaSoft\JDK\21.0.9` → `C:\Program Files\Java\jdk-21`；`Java Development Kit\1.8` → `jdk1.8.0_351` | `Get-ChildItem` + `JavaHome` | `[已复验]` |
| JDK（WOW6432Node） | **不存在** JavaSoft 子键（本机 JDK 均为 64 位） | `Test-Path` | `[已复验]` |
| JDK（PATH） | `javapath\javac.exe` → 21.0.9 | `where javac` + `javac -version` | `[已复验]` |

### 3.3 与版本锁的差距（执行链阻断点）

| 组件 | 锁值（`ToolchainVersions` / VERSION-LOCK） | 本机实际 | 结论 |
|---|---|---|---|
| JDK | `17` | 21（PATH/注册表）、19（失效 JAVA_HOME）、1.8 | ❌ 不匹配（`probe_jdk` 会报 `JdkVersionUnmatched`） |
| build-tools | `34.0.0` | `35.0.0` | ❌ 不匹配 |
| platform | `android-34` | `android-35` | ❌ 不匹配 |
| NDK | `r27` | 缺失 | ❌ 不可用 |
| CMake | `3.22.1` | 未在 PATH / 常见路径 | ❌ 不可用（`MissingTool` 会在计划期拒绝） |

**判定**：即使脚本与 JDK 修复就绪，本机按**锁定版本**仍无法执行完整链路。版本升级/锁值变更须走本仓库「升级与特性开发分离 PR」的独立流程；本次只登记，不改锁。

## 4. Windows JDK 探测设计（已落地部分）

### 4.1 两段式（职责分离）

1. **采集器（组合根，不在本库）**：读 `JAVA_HOME`、注册表、常见安装根目录、`PATH`，并验证目录含 `bin/javac.exe`；产出 `JdkProbeEnv` 快照。
2. **评估器（本库 `probe_jdk`）**：纯函数，按 `JAVA_HOME → 注册表 → 常见路径 → PATH` 排序、按 Windows 规则去重（小写键）、按 `existing_jdk_dirs` 判断存在、按 `required_major` 判断主版本，返回 `JdkProbeResult`（`JdkFound` / `JdkNotFound` / `JdkVersionUnmatched` + 诊断）。

### 4.2 已实现的 Windows 细节

- `JAVA_HOME` 成对双引号剥离（最多两层）、首尾空白 trim；
- `\` → `/`、折叠重复分隔符、去尾部 `/`；拒绝相对路径、`C:` drive-relative、控制字符；
- 大小写不敏感去重（Windows 路径语义），保留首次出现的来源优先级；
- 版本解析：`17` / `17.0.9` / `21-ea` / `1.8.0_202`（→ 8）；不可解析 = 不匹配（fail-closed）；
- 版本缺失（`None`）= 按存在性接受并记诊断（若需严格，组合根必须提供 `release` 版本）；
- `required_major` 不在 8..99 → `InvalidJdkProbe`（畸形输入不 panic）。

### 4.3 采集器建议（`[仅据文档]` + 本机实测键位）

| 来源 | 键 / 位置 | 本机实测 |
|---|---|---|
| `JAVA_HOME` | 环境变量 | 指向失效目录（`[已复验]`） |
| 注册表（现代） | `HKLM\SOFTWARE\JavaSoft\JDK\<version>\JavaHome` | `21.0.9` → `jdk-21`（`[已复验]`） |
| 注册表（旧 JRE/JDK） | `HKLM\SOFTWARE\JavaSoft\Java Development Kit\<version>\JavaHome` | `1.8` → `jdk1.8.0_351`（`[已复验]`） |
| 32 位视图 | `HKLM\SOFTWARE\WOW6432Node\JavaSoft\...` | 本机不存在（`[已复验]`）；其他机器可能有 |
| 常见根 | `C:\Program Files\Java\*`、`C:\Program Files\Eclipse Adoptium\*` 等 | `C:\Program Files\Java` 含 jdk-21 / jdk1.8.0_351（`[已复验]`） |
| `PATH` | `where javac` | 21.0.9（`[已复验]`） |
| 发行商私有键 | 各发行商（如 Adoptium/MSI）命名不同 | `[仍需实测]`（不得假设统一键位） |

**采集器验收要求**：候选目录必须实际包含 `bin/javac.exe`（排除 JRE、残留目录、失效 `JAVA_HOME`）；`release` 文件缺失时版本记 `None` 并在诊断中显式标注。

## 5. 风险登记

| ID | 风险 | 触发/影响 | 缓解（已落地 / 待办） | 状态与证据 |
|---|---|---|---|---|
| R1 | **JAVA_HOME 失效 / 与 PATH 不一致** | d8、apksigner 直接 exit 1（本机已复现） | 已落地：`probe_jdk` 存在性 + 版本匹配 + 来源优先级；待办：组合根采集器与 CI 预检 | 已复现 `[已复验]`；采集器 `[仍需实测]` |
| R2 | **工具版本漂移**（build-tools / platform / NDK / CMake / JDK） | 计划期 `ToolchainNotLocked`/`MissingTool`；运行期命令行为差异 | 已落地：7 必填字段锁、`MissingTool`、CI 版本断言；待办：锁值升级按 本仓库版本升级流程 | 本机 5 项全不匹配 `[已复验]` |
| R3 | **相对路径 / 工作目录不一致** | aapt2 找不到 `res`、`AndroidManifest.xml`、CMake 找不到 `src/native` | 已落地：模板树按计划路径生成（`src/native`、`res`），脚本第 4 阶段 `cd build/android` | 结构测试 `[已复验]`；真实执行 `[仍需实测]` |
| R4 | **缺少 C stub / Java 源** | CMake 无 `stub.c`、javac glob 无可编译文件 | 文档登记为组合根必供输入；计划期无法检测（纯值） | `[仍需实测]` |
| R5 | **Assemble 打包条目路径缺口**（已知，待本仓库维护者决定） | 既有 `render_script` 的 Assemble 行 `$JAR uf <apk> -C out/native/<abi> <soname>` 会把 `.so` 放在 APK **根**而非 `lib/<abi>/`，Android 不加载 | 本轮**未改**既有 golden（红线 4）；模板的 `plan/abi-libs.txt` 与 `jniLibs/<dir>` 已登记正确目标；建议下一轮修复并同步重录既有 golden | 源码审阅 `[已复验-本地等价]`；修复待裁决 |
| R6 | **CMake target 名与输出名** | 计划 `--target <soname>`；模板已把 target 名设为 soname、`OUTPUT_NAME` 设为 stem，理论自洽，但 CMake 对含 `.` 的 target 名行为未实机验证（本机无 cmake） | 文档登记契约；待装 CMake 后实测 | `[仍需实测]` |
| R7 | **脚本注入（模板参数）** | 恶意 `app_name` / 资产路径 / 内容破坏 heredoc 或写出模板根 | 已落地：参数白名单校验、XML 转义、heredoc 分隔符整行检测、路径防穿越；测试覆盖 | `[已复验]`（单元测试） |
| R8 | **双 ABI 不一致** | 缺 32 位 `.so` → armeabi-v7a 设备加载失败；重复 ABI → 清单歧义 | 已落地：`dual_abi_set`、重复/缺失/非法 ABI 名错误路径、`MissingAbi`、哈希登记 fail-closed | `[已复验]`（单元测试）；设备 `[仍需实测]` |
| R9 | **签名与密钥** | 密钥内嵌、方案冲突、zipalign 顺序错误 | 已落地：`KeyMaterialEmbedded` 双入口、`SigningSchemeConflict`、`InvalidStepOrder`；密钥只以 `$KEYSTORE_REF` | `[已复验]`（单元测试）；真实签名 `[仍需实测]` |
| R10 | **adb / 设备授权** | `adb install` 需设备授权、ABI 匹配、系统版本 | 计划只输出 `$ADB install -r`；`adb` 不参与版本锁（设备侧） | `[仍需实测]`（无真机操作） |
| R11 | **许可** | SDK/NDK/build-tools 二进制不可再分发 | 本库只分发文本；模板不下载、不嵌入工具/资产/`.so` 内容 | `[仅据文档]`（Android SDK License 3.4）+ 代码审阅 |
| R12 | **sha256 组合根自动化**（P2） | 产物/资产/`.so` 哈希仍需人工或外部脚本回填 | 本库只校验值规格与登记完整性；自动化未做（P2） | 未做 `[仍需实测]` |

## 6. 已知缺口与待决事项

1. **G-1（R5）Assemble 条目路径**：修复会改变既有 `render_script` golden 文本，按红线 4「golden 不一致须书面记录待评审，禁止静默重录」，本轮**只登记不改**。建议修复：把 `out/native/<abi>/<soname>` 改为 `out/native/<abi>/lib/<soname>` 的 staging 目录，再 `$JAR uf apk -C out/native/<abi> lib/<abi>/<soname>`（具体命令与 golden 需评审通过后重录）。模板已生成 `jniLibs/<dir>` 与 `plan/abi-libs.txt` 作为正确目标布局，但既有 `Assemble` 命令**不消费** `jniLibs`；修复时二者应一并接线。
2. **G-2（R6）CMake target 名**：模板采用「target = soname、OUTPUT_NAME = stem」以贴合计划；若实测 CMake 拒绝含 `.` 的 target 名，则需改计划命令（golden 变更，同样需裁决）。
3. **G-3（§3.3）版本锁 vs 本机实际**：执行链要按锁定值跑通，必须安装 build-tools 34.0.0 / platform android-34 / NDK r27 / JDK 17 / CMake 3.22.1，或按升级流程改锁；本轮不改锁。
4. **G-4（R12）sha256 自动化**：组合根自动计算 `.so` / APK / 资产哈希并调用 `attach_native_hashes`，属 P2。

## 7. P2 未做（如实登记）

- Gradle / IDE 集成：未做。
- Q1「一条命令到设备启动」实证：未做（所需资产不在本仓库内、目标设备未接）。
- sha256 组合根自动化：未做。
- 真实 `.so` / 模型 / devkit：按红线**未下载、未落盘、未链接**；frida G1 未闭环。

## 8. 复核方式

```powershell
cd moon_android
moon check --deny-warn   # 门禁 1
moon build               # 门禁 2
moon test                # 门禁 3（79 tests）
moon fmt --check         # 门禁 4
moon info; git diff --exit-code -- ../pkg.generated.mbti ../cmd/main/pkg.generated.mbti   # 门禁 5
```

本机等价实跑结果见回报与 `TEMPLATE.md` §8；**不是** GitHub Actions 实跑（Actions `[仍需实测]`）。
