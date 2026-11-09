# 模板 → 生成目录树映射（TEMPLATE.md）

> 状态：**R4 已落地**（2026-11-09）｜ 对应 ADR-0005 O6「先一次性脚本、再泛化模板」
> 边界：本库**只产出计划与脚本文本，不执行**。生成目录树由 `render_template_script` 输出的脚本在组合根执行；真实 `.so`、模型、SDK/NDK 二进制**不入库**。

## 1. 为什么现在泛化

ADR-0005 的 O6 决策把「参数化模板」排在「一次性 shell APK 脚本」之后：先用一次性脚本证明 A4（产物能在设备上安装运行），再把已验证的通路抽象成接口。R4 把**能抽象的纯值部分**先行落地：

- 输入：包名 / 应用名 / ABI 集合 / 模块依赖 / 资产注入 / 既有 `BuildConfig`；
- 中间：`plan_template` 产出 `GeneratedTree`（生成文件 + 双 ABI 布局 + `BuildPlan`）；
- 输出：`render_template_script` 产出「按计划执行」的四阶段确定性脚本。

设备端「一条命令到设备启动」**仍未实测**（Q1/E3），模板化**不改变**这一事实；它只是把已确定的计划层与脚本层固定为可测试接口。

## 2. 参数表

| 参数 | 类型 | 作用 | 进入生成物的位置 |
|---|---|---|---|
| `config.package_id.name` | `String` | Android 包名 | `AndroidManifest.xml` 的 `package`；产物基名；soname（末段） |
| `app_name` | `String` | 应用显示名（非空、无控制字符、≤64 字符） | `res/values/strings.xml` 的 `app_name`（XML 转义） |
| `config.abis` | `Array[Abi]` | 生效 ABI 集合（R4 双 ABI 基线 = `arm64-v8a` + `armeabi-v7a`） | `plan/abi-libs.txt`、`jniLibs/<dir>/`、`CrossCompile`/`Assemble` 命令 |
| `module_deps` | `Array[String]` | **模块依赖文本契约**（如 `hnlyxiaobing/moon_abi`、`bobzhang/zip@0.1.2`） | `plan/module-deps.txt`（本库不 import、不写 `moon.pkg`） |
| `assets` | `Array[AssetInjection]` | 资产注入声明（源路径 / `assets/` 目标 / SHA-256） | `plan/assets.txt` + 脚本第 3 阶段的 `sha256sum -c` 与 `cp` |
| `config.activity` | `ActivityKind` | 壳 Activity 种类 | `AndroidManifest.xml` 的 shell 类名（`.MoonWebViewActivity` / `.MoonGlesActivity` / `.MoonNativeActivity`） |
| `config.entry_url` | `String?` | WebView 入口 URL | `AndroidManifest.xml` 的 `moon_android.entry_url` meta-data（XML 转义；`None` 不生成） |
| `config.min_sdk` / `target_sdk` | `Int32` | SDK 范围 | `AndroidManifest.xml` 的 `uses-sdk` |
| `config.signing_schemes` / `keystore_ref` | `Array[SigningScheme]` / `String` | 签名方案与密钥引用 | `BuildPlan` 的 `Apksigner` 步骤（`--vN-signing-enabled`；密钥只以 `$KEYSTORE_REF` 出现） |
| `config.toolchain` | `ToolchainVersions` | 版本锁（7 必填 + 可选 cmake） | `src/native/CMakeLists.txt` 的 `cmake_minimum_required`；脚本文本头部的版本注释；`$AAPT2` 等工具版本来源 |

## 3. 生成目录树（模板根固定 `build/android`）

| # | 生成路径 | `GeneratedKind` | 内容来源 | 消费方 |
|---|---|---|---|---|
| 1 | `AndroidManifest.xml` | `ManifestXml` | 包名 / SDK / 壳 Activity / 可选 entry_url | aapt2 link（`--manifest`） |
| 2 | `res/values/strings.xml` | `StringsXml` | `app_name`（XML 转义） | aapt2 compile/link |
| 3 | `src/native/CMakeLists.txt` | `NativeBuild` | soname（target 名 = soname，`OUTPUT_NAME` = stem）/ CMake 版本（来自版本锁） | NDK 交叉编译（`$CMAKE -S src/native`） |
| 4 | `plan/module-deps.txt` | `ModuleDeps` | `module_deps`（文本契约） | 组合根写目标 App 的 `moon.pkg` |
| 5 | `plan/abi-libs.txt` | `AbiManifest` | ABI 目录 + soname → APK 条目 `lib/<dir>/<soname>` | 发布审计 / 双 ABI 核对 |
| 6 | `plan/assets.txt` | `AssetManifest` | `assets` 三元组（target ← source + sha256） | 组合根校验与归档 |
| 7 | `jniLibs/<abi-dir>/` | 目录（脚本第 2 阶段） | ABI 集合 | 期望 `.so` 落点（构建后由组合根放入） |
| 8 | `assets/<target>` | 运行时文件（脚本第 3 阶段） | `assets` 声明（先 `sha256sum -c` 再 `cp`） | APK 资产 |
| 9 | `build.sh`（可选持久化） | 脚本文本（`render_template_script` 返回值） | 上述全部 | 审阅 / 由组合根决定是否执行 |

生成树的完整形态（双 ABI + 1 个资产示例）：

```text
build/android/
├── AndroidManifest.xml
├── res/values/strings.xml
├── src/native/CMakeLists.txt   # stub.c 由组合根提供（不生成）
├── plan/
│   ├── module-deps.txt
│   ├── abi-libs.txt
│   └── assets.txt
├── jniLibs/
│   ├── arm64-v8a/          # 期望 libapp.so（构建后由组合根放入）
│   └── armeabi-v7a/        # 期望 libapp.so
└── assets/
    └── index.html          # 脚本校验 SHA-256 后复制
```

`files` 的顺序固定为表中 1–6；脚本的 `mkdir` 与 heredoc 也按该顺序生成（同输入逐字一致）。

**相对路径对齐**：计划的命令使用相对路径（`$CMAKE -S src/native`、`$AAPT2 compile --dir res`、`--manifest AndroidManifest.xml`、`gen/`、`out/`）。脚本第 4 阶段先 `cd build/android` 再执行计划，因此生成目录内的 `src/native`、`res`、`AndroidManifest.xml` 与计划一致。

**组合根必须提供的输入**（模板不生成、不读取）：`src/native/stub.c`（C stub 源码）、`src/java/*.java` 与 `gen/*.java`（壳 Activity / 生成代码）、签名密钥（只以 `$KEYSTORE_REF` 引用）。缺少这些输入时脚本语义仍然确定，但真实执行会失败——属执行链风险，见 `EXECUTION-CHAIN.md`。

## 4. 脚本四阶段（`render_template_script`）

```sh
#!/bin/sh
# rendered by moon_android::render_template_script — deterministic review artifact; DO NOT EXECUTE
# template root: build/android
...
# --- 1/4 materialize generated tree (6 files) ---
mkdir -p build/android
mkdir -p build/android/res/values
cat > build/android/AndroidManifest.xml <<'MOON_ANDROID_EOF_0'
...
MOON_ANDROID_EOF_0
...
# --- 2/4 ABI layout (2 dirs) ---
mkdir -p build/android/jniLibs/arm64-v8a
# expected APK entry: lib/arm64-v8a/libapp.so (sha256=unregistered)
...
# --- 3/4 asset injection (1 assets; sha256 verified before copy) ---
mkdir -p build/android/assets
echo '<sha256>  web/index.html' | sha256sum -c -
cp 'web/index.html' 'build/android/assets/index.html'
# --- 4/4 build plan (10 steps) ---
cd build/android
# rendered by moon_android::render_template_script ...
# [1/10] CrossCompile
...
```

1. **物化生成目录树**：每个 `GeneratedFile` 一个 heredoc；分隔符按序号唯一（`MOON_ANDROID_EOF_<i>`），内容若含同名**整行**则拒绝渲染（`InvalidTemplate`），防脚本注入。
2. **ABI 布局**：为每个 ABI 建 `jniLibs/<dir>`，并以注释登记期望 APK 条目 `lib/<dir>/<soname>`；`sha256=unregistered` 是显式未登记状态，不是通过。
3. **资产注入**：`sha256sum -c -` 先校验声明哈希再 `cp`；资产内容**不进入**库，也**不入库**（红线：真实资产只登记路径 + SHA-256）。
4. **构建计划**：先 `cd build/android`，再复用 `plan_steps_text`，与 `render_script` 输出**同一份**命令模板（`$CMAKE`/`$AAPT2`/`$JAVAC`/`$D8`/`$JAR`/`$ZIPALIGN`/`$APKSIGNER`/`$ADB`）。

脚本头部的 `DO NOT EXECUTE` 与 `render_script` 一致：本库不 spawn 进程；是否执行、如何注入真实工具路径由组合根负责（风险见 `EXECUTION-CHAIN.md`）。

## 5. 错误路径（全部 `raise MoonAndroidError`，畸形输入不 panic）

| 错误 | 触发 | 代表测试 |
|---|---|---|
| `InvalidPackage` | 包名不合 Android 规则 | `plan_template 配置错误原样传播` |
| `ToolchainNotLocked` | 7 个必锁字段任一为空 | 同上 |
| `KeyMaterialEmbedded` | `keystore_ref` 含 PEM / password / base64 等信号 | `plan_template 配置错误原样传播`、`render_template_script 篡改树` |
| `SigningSchemeConflict` | 空/重复方案、`min_sdk < 24` 缺 V1、V31 缺 V3 | 既有签名测试 + 模板传播 |
| `UnsupportedAbi` | ABI 集为空 / 重复 / 非法 ABI 名 | ABI 测试 + 模板传播 |
| `MissingTool` | 计划所需工具在版本锁中缺失（如 cmake） | `render_template_script 篡改树` |
| `InvalidTemplate` | app_name 非法；module_deps 非法/重复；根/文件路径非法或重复；content 含分隔符 | `plan_template 非法 app_name`、`非法/重复 module_deps`、`篡改树` |
| `InvalidAsset` | source/target 路径穿越、SHA-256 非法、target 重复 | `plan_template 非法资产声明` |
| `InvalidNativeLib` | soname 非法（目录穿越/后缀不符） | ABI 测试 |

## 6. 确定性约定

- `plan_template` 纯函数：不读环境、不读文件、不写文件；同输入同输出。
- `files` 顺序固定（§3 表 1–6），不受调用方数组顺序影响（`assets` 保持声明顺序）。
- `abi-libs.txt` 与 `jniLibs` 目录按 `config.abis` 输入顺序（不重排），避免隐式排序导致快照漂移。
- 脚本只在 `DEBUG` 类渲染中负责文本，不包含时间戳、主机路径、随机数。

## 7. 非目标（R4 范围外）

- **不执行**脚本、不签名、不调 adb、不产出 APK。
- **不写** `moon.pkg`（`module_deps` 只是文本契约；跨模块零 import 见 ADR-0002）。
- **不实现** Gradle / IDE 集成（P2）。
- **不下载** SDK/NDK/JDK；**不随附**任何工具二进制（Android SDK License 3.4）。
- **不嵌入**资产内容或 `.so` 本体；只登记路径与 SHA-256。
- **未覆盖**：`build.sh` 在真实 shell 下的执行、真实 aapt2/d8/zipalign/apksigner 行为、设备安装与启动 —— 全部 `[仍需实测]`（见 `EXECUTION-CHAIN.md`）。

## 8. 验收与证据

- 测试：`moon test` **79 passed / 0 failed**（2026-11-09 本机实测；含模板 16 项、ABI 11 项、JDK 13 项新增）。
- 门禁：`moon check --deny-warn` / `moon build` / `moon test` / `moon fmt --check` / 第 5 道快照门禁全绿（本机等价实跑，非 GitHub Actions）。
- 示例 golden：`moon_android_test.mbt` 的 `render_script golden`（既有，逐字未变）+ `template_test.mbt` 的 `render_template_script golden`（新增，单 ABI 全脚本）。
- 设备端：**未实测**（Q1/E3，`[仍需实测]`）。
