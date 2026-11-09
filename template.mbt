///|
/// 通用模板：把「一次性 shell APK 脚本」验证通路抽象为
/// **参数化模板**。
///
/// 输入 `TemplateParams`（包名 / 应用名 / ABI 集合 / 模块依赖 / 资产注入 /
/// 既有 BuildConfig），输出纯值 `GeneratedTree`（生成目录树 + native 库布局
/// + BuildPlan），再由 `render_template_script` 渲染「按计划执行」的确定性
/// 脚本文本。
///
/// 边界：本文件仍然**不执行**任何命令、不读写文件、不下载工具；脚本由
/// 组合根执行或审阅。模板 → 生成目录树的映射见 `docs/TEMPLATE.md`。

///|
/// 资产注入声明。资产内容**不入库**：只登记源路径、APK 内目标路径与
/// SHA-256（由组合根计算并校验）。
///
/// - `source`：相对本仓库根目录的源文件路径（`[A-Za-z0-9_.-]` 与 `/`，禁穿越）；
/// - `target`：`assets/` 下的相对路径（禁穿越、禁重复）；
/// - `sha256`：64 位十六进制。
pub(all) struct AssetInjection {
  source : String
  target : String
  sha256 : String
}

///|
/// 模板参数：在既有 `BuildConfig` 之上增加模板专属字段。
///
/// - `config.package_id` = 包名；`config.abis` = ABI 集合；
/// - `app_name` 写入 `res/values/strings.xml` 的 `app_name`；
/// - `module_deps` 是**文本契约**（组合根据此写目标 App 的 `moon.pkg`），
///   本库不 import 任何模块；
/// - `assets` 为资产注入声明（只登记路径与哈希）。
pub(all) struct TemplateParams {
  config : BuildConfig
  app_name : String
  module_deps : Array[String]
  assets : Array[AssetInjection]
}

///|
/// 生成文件的种类（用于审阅与测试断言，不参与文件路径计算）。
pub(all) enum GeneratedKind {
  ManifestXml
  StringsXml
  NativeBuild
  ModuleDeps
  AbiManifest
  AssetManifest
}

///|
/// 生成文件：相对模板根的路径 + 种类 + 确定性文本内容。
pub(all) struct GeneratedFile {
  path : String
  kind : GeneratedKind
  content : String
}

///|
/// 模板生成计划（纯值，不含可执行动作）。
///
/// - `root`：生成根（固定 `build/android`，相对本仓库根目录）；
/// - `files`：生成的声明式文件（顺序固定，见 `docs/TEMPLATE.md`）；
/// - `native_libs`：双 ABI `.so` 布局（`sha256 = None`，构建后由
///   `attach_native_hashes` 回填）；
/// - `assets`：资产注入声明（渲染脚本时重新校验）；
/// - `build_plan`：`plan_build` 产出的规范 10 步计划。
pub(all) struct GeneratedTree {
  root : String
  app_name : String
  files : Array[GeneratedFile]
  native_libs : Array[NativeLib]
  assets : Array[AssetInjection]
  build_plan : BuildPlan
}

///|
/// 模板生成根（相对本仓库根目录，固定值）。
fn template_root() -> String {
  "build/android"
}

///|
/// 内部助手：控制字符（含换行 / 制表 / DEL）。
fn is_control_char(c : Char) -> Bool {
  let code = c.to_int()
  code < 32 || code == 127
}

///|
/// 内部助手：应用名合法性——trim 后非空、无控制字符、长度 ≤ 64 字符。
/// 应用名会进入 XML 文本节点，特殊字符由 `xml_escape` 转义而不是拒绝。
fn valid_app_name(name : String) -> Bool {
  if name.trim().is_empty() {
    return false
  }
  let chars = name.to_array()
  if chars.length() > 64 {
    return false
  }
  for c in chars {
    if is_control_char(c) {
      return false
    }
  }
  true
}

///|
/// 内部助手：XML 文本 / 属性转义（`& < > " '`）。
fn xml_escape(s : String) -> String {
  let mut out = ""
  for c in s.to_array() {
    if c == '&' {
      out = out + "&amp;"
    } else if c == '<' {
      out = out + "&lt;"
    } else if c == '>' {
      out = out + "&gt;"
    } else if c == '"' {
      out = out + "&quot;"
    } else if c == '\'' {
      out = out + "&apos;"
    } else {
      out = out + "\{c}"
    }
  }
  out
}

///|
/// 内部助手：相对路径合法性（防目录穿越 / 盘符 / 反斜杠 / 空段）。
/// 允许字符：`[A-Za-z0-9_.-]` 与 `/`；段不得为 `.` 或 `..`、不得以 `/`
/// 开头或结尾。生成文件与资产路径共用该规则。
fn relative_path_ok(path : String) -> Bool {
  if path.is_empty() {
    return false
  }
  let chars = path.to_array()
  if chars[0] == '/' {
    return false
  }
  let mut seg = ""
  for c in chars {
    if c == '/' {
      if seg == "" || seg == "." || seg == ".." {
        return false
      }
      seg = ""
    } else {
      let ok = (c >= 'a' && c <= 'z') ||
        (c >= 'A' && c <= 'Z') ||
        (c >= '0' && c <= '9') ||
        c == '_' ||
        c == '-' ||
        c == '.'
      if !ok {
        return false
      }
      seg = seg + "\{c}"
    }
  }
  if seg == "" || seg == "." || seg == ".." {
    return false
  }
  true
}

///|
/// 内部助手：模块依赖文本合法性（如 `hnlyxiaobing/moon_abi`、
/// `bobzhang/zip@0.1.2`）。允许 `[A-Za-z0-9_.@-]` 与 `/`；段不得为空 /
/// `.` / `..`。
fn valid_module_dep(dep : String) -> Bool {
  if dep.is_empty() {
    return false
  }
  let mut seg = ""
  for c in dep.to_array() {
    if c == '/' {
      if seg == "" || seg == "." || seg == ".." {
        return false
      }
      seg = ""
    } else {
      let ok = (c >= 'a' && c <= 'z') ||
        (c >= 'A' && c <= 'Z') ||
        (c >= '0' && c <= '9') ||
        c == '_' ||
        c == '.' ||
        c == '-' ||
        c == '@'
      if !ok {
        return false
      }
      seg = seg + "\{c}"
    }
  }
  if seg == "" || seg == "." || seg == ".." {
    return false
  }
  true
}

///|
/// 内部助手：资产声明校验——路径合法、SHA-256 为 64 位十六进制、
/// `target` 不重复。任何违规 → `InvalidAsset`。
fn validate_assets(
  assets : Array[AssetInjection],
) -> Unit raise MoonAndroidError {
  for i in 0..<assets.length() {
    let asset = assets[i]
    if !relative_path_ok(asset.source) {
      raise InvalidAsset("source 路径非法：" + asset.source)
    }
    if !relative_path_ok(asset.target) {
      raise InvalidAsset("target 路径非法：" + asset.target)
    }
    if !is_sha256_hex(asset.sha256) {
      raise InvalidAsset(
        "sha256 非法（需 64 位十六进制）：" + asset.target,
      )
    }
    for j in (i + 1)..<assets.length() {
      if asset.target == assets[j].target {
        raise InvalidAsset("重复的 asset target：" + asset.target)
      }
    }
  }
}

///|
/// 内部助手：数组是否包含某字符串。
fn contains_str(items : Array[String], want : String) -> Bool {
  for item in items {
    if item == want {
      return true
    }
  }
  false
}

///|
/// 内部助手：`lib<stem>.so` 的 stem（调用前必须已通过库名校验）。
fn soname_stem(name : String) -> String {
  let chars = name.to_array()
  let n = chars.length()
  let mut out = ""
  for i in 3..<(n - 3) {
    out = out + "\{chars[i]}"
  }
  out
}

///|
/// 内部助手：相对路径的父目录（无 `/` 时返回空串）。
fn parent_dir(path : String) -> String {
  let chars = path.to_array()
  let mut last = -1
  for i in 0..<chars.length() {
    if chars[i] == '/' {
      last = i
    }
  }
  if last <= 0 {
    return ""
  }
  let mut out = ""
  for i in 0..<last {
    out = out + "\{chars[i]}"
  }
  out
}

///|
/// 内部助手：文本是否包含某一行完全等于 `line`（用于脚本 heredoc 分隔符
/// 冲突检查）。
fn contains_line(text : String, line : String) -> Bool {
  let mut cur = ""
  for c in text.to_array() {
    if c == '\n' {
      if cur == line {
        return true
      }
      cur = ""
    } else {
      cur = cur + "\{c}"
    }
  }
  cur == line
}

///|
/// 内部助手：文本是否以换行结尾。
fn ends_with_newline(text : String) -> Bool {
  let chars = text.to_array()
  if chars.length() == 0 {
    return false
  }
  chars[chars.length() - 1] == '\n'
}

///|
/// 内部助手：壳 Activity 的 Java 类名（相对包名）。
fn activity_class(activity : ActivityKind) -> String {
  match activity {
    WebView => ".MoonWebViewActivity"
    GlesSurface => ".MoonGlesActivity"
    NativeOnly => ".MoonNativeActivity"
  }
}

///|
/// 内部助手：生成 `AndroidManifest.xml`（包名 / 版本 / 壳 Activity /
/// 可选 entry_url meta-data；XML 转义）。
fn render_manifest(config : BuildConfig) -> String {
  let mut text = "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"
  text = text +
    "<manifest xmlns:android=\"http://schemas.android.com/apk/res/android\"\n"
  text = text + "    package=\"" + config.package_id.name + "\">\n"
  text = text +
    "  <uses-sdk android:minSdkVersion=\"" +
    "\{config.min_sdk}" +
    "\" android:targetSdkVersion=\"" +
    "\{config.target_sdk}" +
    "\" />\n"
  text = text +
    "  <application android:label=\"@string/app_name\" android:hasCode=\"true\">\n"
  match config.entry_url {
    Some(url) =>
      text = text +
        "    <meta-data android:name=\"moon_android.entry_url\" android:value=\"" +
        xml_escape(url) +
        "\" />\n"
    None => ()
  }
  text = text +
    "    <activity android:name=\"" +
    activity_class(config.activity) +
    "\" android:exported=\"true\">\n"
  text = text +
    "      <intent-filter>\n        <action android:name=\"android.intent.action.MAIN\" />\n"
  text = text +
    "        <category android:name=\"android.intent.category.LAUNCHER\" />\n      </intent-filter>\n"
  text = text + "    </activity>\n  </application>\n</manifest>\n"
  text
}

///|
/// 内部助手：生成 `res/values/strings.xml`（app_name 转义）。
fn render_strings(app_name : String) -> String {
  "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<resources>\n  <string name=\"app_name\">" +
  xml_escape(app_name) +
  "</string>\n</resources>\n"
}

///|
/// 内部助手：生成 `src/native/CMakeLists.txt`（与计划的 `$CMAKE -S src/native`
/// 对齐；target 名 = soname，满足计划里的 `--target <soname>`；输出文件名
/// 由 `OUTPUT_NAME` 固定为 `lib<stem>.so`）。
fn render_cmake(config : BuildConfig) -> String {
  let library = soname(config)
  let stem = soname_stem(library)
  let cmake_version = match config.toolchain.cmake {
    Some(version) => version
    None => "3.22.1"
  }
  let mut text = "# generated by moon_android::plan_template — review artifact\n"
  text = text + "cmake_minimum_required(VERSION " + cmake_version + ")\n"
  text = text + "project(moon_android_app C)\n"
  text = text + "set(MOON_ANDROID_SONAME \"" + library + "\")\n"
  text = text + "add_library(" + library + " SHARED stub.c)\n"
  text = text + "set_target_properties(" + library + " PROPERTIES\n"
  text = text + "  OUTPUT_NAME \"" + stem + "\"\n"
  text = text + "  PREFIX \"lib\"\n"
  text = text + "  SUFFIX \".so\")\n"
  text = text + "target_link_libraries(" + library + " log)\n"
  text
}

///|
/// 内部助手：生成 `plan/module-deps.txt`（文本契约，按输入顺序）。
fn render_module_deps(deps : Array[String]) -> String {
  let mut text = "# generated by moon_android::plan_template — module deps (text contract)\n"
  text = text +
    "# moon_android never imports these modules; the composition root writes moon.pkg\n"
  text = text + "# count: \{deps.length()}\n"
  if deps.length() == 0 {
    text = text + "# (none)\n"
  } else {
    for dep in deps {
      text = text + dep + "\n"
    }
  }
  text
}

///|
/// 内部助手：生成 `plan/abi-libs.txt`（双 ABI 布局，一行一 ABI）。
fn render_abi_libs(libs : Array[NativeLib]) -> String {
  let mut text = "# generated by moon_android::plan_template — ABI layout\n"
  text = text + "# <abi dir> <soname> -> APK entry lib/<abi dir>/<soname>\n"
  for lib in libs {
    text = text +
      lib.dir +
      " " +
      lib.soname +
      " -> lib/" +
      lib.dir +
      "/" +
      lib.soname +
      "\n"
  }
  text
}

///|
/// 内部助手：生成 `plan/assets.txt`（资产注入登记）。
fn render_assets(assets : Array[AssetInjection]) -> String {
  let mut text = "# generated by moon_android::plan_template — asset injection registry\n"
  text = text +
    "# content is never stored by moon_android; sha256 is computed and verified by the composition root\n"
  text = text + "# target <- source sha256=<hex>\n"
  if assets.length() == 0 {
    text = text + "# (none)\n"
  } else {
    for asset in assets {
      text = text +
        asset.target +
        " <- " +
        asset.source +
        " sha256=" +
        asset.sha256 +
        "\n"
    }
  }
  text
}

///|
/// 生成模板计划（纯计算，不执行、不读写文件）。
///
/// - 参数：`params.config` 走 `plan_build` 的全部配置校验；`app_name`
///   非空 / 无控制字符 / ≤64 字符；`module_deps` 为文本契约；`assets`
///   只登记路径与 SHA-256。
/// - 返回：`GeneratedTree`，包含固定 6 个生成文件、ABI 布局与规范 10 步
///   `BuildPlan`。
/// - 错误（按校验次序）：`InvalidPackage` / `ToolchainNotLocked` /
///   `KeyMaterialEmbedded` / `SigningSchemeConflict` / `UnsupportedAbi` /
///   `MissingTool`（来自 `plan_build`）；`InvalidTemplate`（app_name /
///   module_deps）；`InvalidAsset`（资产路径 / 哈希 / 重复 target）；
///   `InvalidNativeLib`（soname）。
/// - 线程：纯函数，无状态，可并发调用。
pub fn plan_template(
  params : TemplateParams,
) -> GeneratedTree raise MoonAndroidError {
  let plan = plan_build(params.config, [])
  if !valid_app_name(params.app_name) {
    raise InvalidTemplate(
      "app_name 非法（需非空、无控制字符、≤64 字符）：" +
      params.app_name,
    )
  }
  let seen : Array[String] = []
  for dep in params.module_deps {
    if !valid_module_dep(dep) {
      raise InvalidTemplate("module_dep 非法：" + dep)
    }
    if contains_str(seen, dep) {
      raise InvalidTemplate("重复的 module_dep：" + dep)
    }
    seen.push(dep)
  }
  validate_assets(params.assets)
  let native_libs = plan_native_libs(plan.config.abis, soname(plan.config))
  let files : Array[GeneratedFile] = []
  files.push({
    path: "AndroidManifest.xml",
    kind: ManifestXml,
    content: render_manifest(plan.config),
  })
  files.push({
    path: "res/values/strings.xml",
    kind: StringsXml,
    content: render_strings(params.app_name),
  })
  files.push({
    path: "src/native/CMakeLists.txt",
    kind: NativeBuild,
    content: render_cmake(plan.config),
  })
  files.push({
    path: "plan/module-deps.txt",
    kind: ModuleDeps,
    content: render_module_deps(params.module_deps),
  })
  files.push({
    path: "plan/abi-libs.txt",
    kind: AbiManifest,
    content: render_abi_libs(native_libs),
  })
  files.push({
    path: "plan/assets.txt",
    kind: AssetManifest,
    content: render_assets(params.assets),
  })
  {
    root: template_root(),
    app_name: params.app_name,
    files,
    native_libs,
    assets: params.assets,
    build_plan: plan,
  }
}

///|
/// 把模板计划渲染为「按计划执行」的确定性脚本文本（仍**不执行**）。
///
/// 四个阶段（顺序固定）：
/// 1. 物化生成目录树（每个 `GeneratedFile` 一个 heredoc，分隔符按序号唯一，
///    内容若含同名整行则拒绝渲染 → `InvalidTemplate`）；
/// 2. ABI 布局（`jniLibs/<dir>` 目录 + 期望 APK 条目注释，双 ABI 基线）；
/// 3. 资产注入（`sha256sum -c -` 先校验再复制；哈希来自声明，不读文件）；
/// 4. 构建计划（复用 `plan_steps_text`，与 `render_script` 同一份命令模板）。
///
/// - 确定性：同输入两次渲染逐字相等；`GeneratedTree` 的文件顺序决定输出。
/// - 错误：`KeyMaterialEmbedded`（密钥内嵌）、`InvalidStepOrder` /
///   `MissingTool`（计划非法或被篡改）、`InvalidTemplate`（根 / 文件路径
///   非法或重复、content 含分隔符）、`InvalidAsset`、`InvalidNativeLib`。
/// - 非目标：不 spawn 进程、不读写文件、不执行 `sha256sum`。
pub fn render_template_script(
  tree : GeneratedTree,
) -> String raise MoonAndroidError {
  let plan = tree.build_plan
  let config = plan.config
  if looks_like_key_material(config.keystore_ref) {
    raise KeyMaterialEmbedded
  }
  validate_step_order(plan.steps)
  validate_tools(plan.steps, config.toolchain)
  if !relative_path_ok(tree.root) {
    raise InvalidTemplate("生成根目录非法：" + tree.root)
  }
  if !valid_app_name(tree.app_name) {
    raise InvalidTemplate("app_name 非法：" + tree.app_name)
  }
  for i in 0..<tree.files.length() {
    let file = tree.files[i]
    if !relative_path_ok(file.path) {
      raise InvalidTemplate("生成文件路径非法：" + file.path)
    }
    for j in (i + 1)..<tree.files.length() {
      if file.path == tree.files[j].path {
        raise InvalidTemplate("生成文件路径重复：" + file.path)
      }
    }
    if contains_line(file.content, heredoc_marker(i)) {
      raise InvalidTemplate(
        "生成文件内容包含脚本分隔符：" + file.path,
      )
    }
  }
  validate_assets(tree.assets)
  validate_native_lib_entries(tree.native_libs)
  let abi_names : Array[String] = []
  for abi in config.abis {
    abi_names.push(abi_name(abi))
  }
  let mut text = "#!/bin/sh\n"
  text = text +
    "# rendered by moon_android::render_template_script — deterministic review artifact; DO NOT EXECUTE\n"
  text = text + "# template root: " + tree.root + "\n"
  text = text + "# package_id: " + config.package_id.name + "\n"
  text = text + "# app_name: " + tree.app_name + "\n"
  text = text + "# abis: " + join_comma(abi_names) + "\n"
  text = text + "# generated files: \{tree.files.length()}\n"
  text = text + "# assets: \{tree.assets.length()}\n"
  // --- 阶段 1：物化生成目录树 ---
  text = text +
    "\n# --- 1/4 materialize generated tree (\{tree.files.length()} files) ---\n"
  text = text + "mkdir -p " + tree.root + "\n"
  let dirs : Array[String] = []
  for file in tree.files {
    let parent = parent_dir(file.path)
    if parent != "" {
      let target = tree.root + "/" + parent
      if !contains_str(dirs, target) {
        dirs.push(target)
      }
    }
  }
  for dir in dirs {
    text = text + "mkdir -p " + dir + "\n"
  }
  for i in 0..<tree.files.length() {
    let file = tree.files[i]
    let marker = heredoc_marker(i)
    text = text +
      "cat > " +
      tree.root +
      "/" +
      file.path +
      " <<'" +
      marker +
      "'\n"
    text = text + file.content
    if !ends_with_newline(file.content) {
      text = text + "\n"
    }
    text = text + marker + "\n"
  }
  // --- 阶段 2：ABI 布局 ---
  text = text +
    "\n# --- 2/4 ABI layout (\{tree.native_libs.length()} dirs) ---\n"
  for lib in tree.native_libs {
    text = text + "mkdir -p " + tree.root + "/jniLibs/" + lib.dir + "\n"
    let hash = match lib.sha256 {
      Some(value) => value
      None => "unregistered"
    }
    text = text +
      "# expected APK entry: lib/" +
      lib.dir +
      "/" +
      lib.soname +
      " (sha256=" +
      hash +
      ")\n"
  }
  // --- 阶段 3：资产注入 ---
  text = text +
    "\n# --- 3/4 asset injection (\{tree.assets.length()} assets; sha256 verified before copy) ---\n"
  if tree.assets.length() > 0 {
    text = text + "mkdir -p " + tree.root + "/assets\n"
  }
  for asset in tree.assets {
    let parent = parent_dir(asset.target)
    if parent != "" {
      text = text + "mkdir -p " + tree.root + "/assets/" + parent + "\n"
    }
    text = text +
      "echo '" +
      asset.sha256 +
      "  " +
      asset.source +
      "' | sha256sum -c -\n"
    text = text +
      "cp '" +
      asset.source +
      "' '" +
      tree.root +
      "/assets/" +
      asset.target +
      "'\n"
  }
  // --- 阶段 4：构建计划 ---
  // 先进入模板根，使计划里的相对路径（src/native、res、AndroidManifest.xml、
  // gen、out）与生成目录树一致。
  text = text + "\n# --- 4/4 build plan (\{plan.steps.length()} steps) ---\n"
  text = text + "cd " + tree.root + "\n"
  text = text + plan_steps_text(plan, "render_template_script")
  text
}

///|
/// 内部助手：第 `index` 个生成文件的 heredoc 分隔符（序号唯一）。
fn heredoc_marker(index : Int32) -> String {
  "MOON_ANDROID_EOF_" + "\{index}"
}
