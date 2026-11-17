///|
/// moon-android-cli：Android 打包链计划层薄 CLI（hnlyxiaobing/moon_android
/// 公开 API 驱动；W8 裁决采纳 A 案）。
///
/// 契约：退出码 0=成功 / 1=校验失败（stderr 打印库错误变体名）/ 2=用法错误。
/// stdout 只输出渲染文本 / 门禁清单 / 探测报告，永不输出密钥材料。
/// 边界：不执行打包、不读密钥文件、不做 JSON 解析（组合根最薄形态）。

///|
let tool_name = "moon-android-cli"

///|
/// 帮助文本（stdout，exit 0）。
fn usage_text() -> String {
  let lines = [
    "\{tool_name} —— Android 打包链计划层薄 CLI（纯值计划 / 可审阅脚本，不执行）",
    "",
    "用法:",
    "  \{tool_name} gates",
    "      输出建议门禁序列（7 行；仅为建议，不代表 CI 实况）",
    "  \{tool_name} render [flags]",
    "      渲染十步构建计划脚本文本（DO NOT EXECUTE 头 + set -eu）",
    "  \{tool_name} template [flags] [--app-name <name>]",
    "      渲染模板四阶段脚本（生成目录树 / ABI 布局 / 资产 / 构建计划）",
    "  \{tool_name} probe-jdk [--required-major <n>] [--java-home <dir>]",
    "      [--java-version <v>] [--existing <dir,dir>] [--strict]",
    "      纯评估 JDK 探测（零 I/O；--strict 下版本未提供即拒绝）",
    "  \{tool_name} --help",
    "",
    "render / template 公共 flags（缺省即演示配置）:",
    "  --package <id>          包名（默认 com.example.app）",
    "  --abis <a,b>            ABI 目录名逗号列表（默认 arm64-v8a）",
    "  --min-sdk <n>           最低 SDK（默认 24）",
    "  --target-sdk <n>        目标 SDK（默认 34）",
    "  --schemes <V1,V2,V3,V31> 签名方案逗号列表（默认 V2,V3）",
    "  --keystore-ref <ref>    密钥引用（默认 @keys/release.jks；禁内嵌密钥）",
    "  --activity <webview|gles|native>  壳类型（默认 webview）",
    "  --entry-url <url>       入口 URL（默认 https://example.com/index.html）",
    "  --profile <debug|release>  构建剖面（默认 debug）",
    "",
    "退出码: 0=成功 1=校验失败（stderr 变体名） 2=用法错误",
  ]
  let mut text = ""
  for line in lines {
    text = text + line + "\n"
  }
  text
}

///|
/// 内置工具链锁（与测试夹具同值；版本锁策略见根 README.md §2）。
fn locked_toolchain() -> @moon_android.ToolchainVersions {
  {
    moon_cli: "moon 0.1.20261104",
    moonc: "v0.10.20+65efd5b93",
    core: "0.1.0",
    ndk: "r27",
    build_tools: "34.0.0",
    platform: "android-34",
    jdk: "17",
    cmake: Some("3.22.1"),
  }
}

///|
/// 库错误 → 变体名文本（跨包只读约束：只 match、不构造）。
fn error_variant(e : Error) -> String {
  match e {
    @moon_android.MoonAndroidError::InvalidPackage(_) => "InvalidPackage"
    @moon_android.MoonAndroidError::UnsupportedAbi(_) => "UnsupportedAbi"
    @moon_android.MoonAndroidError::MissingTool(_) => "MissingTool"
    @moon_android.MoonAndroidError::ToolchainNotLocked(_) =>
      "ToolchainNotLocked"
    @moon_android.MoonAndroidError::InvalidStepOrder(_, _) => "InvalidStepOrder"
    @moon_android.MoonAndroidError::KeyMaterialEmbedded => "KeyMaterialEmbedded"
    @moon_android.MoonAndroidError::SigningSchemeConflict(_) =>
      "SigningSchemeConflict"
    @moon_android.MoonAndroidError::ArtifactMismatch(_) => "ArtifactMismatch"
    @moon_android.MoonAndroidError::MissingGate(_) => "MissingGate"
    @moon_android.MoonAndroidError::MissingAbi(_) => "MissingAbi"
    @moon_android.MoonAndroidError::InvalidNativeLib(_) => "InvalidNativeLib"
    @moon_android.MoonAndroidError::InvalidAsset(_) => "InvalidAsset"
    @moon_android.MoonAndroidError::InvalidTemplate(_) => "InvalidTemplate"
    @moon_android.MoonAndroidError::InvalidJdkProbe(_) => "InvalidJdkProbe"
    _ => "UnknownError"
  }
}

///|
/// 门禁 → 标签。
fn gate_label(gate : @moon_android.Gate) -> String {
  match gate {
    @moon_android.Gate::FmtCheck => "FmtCheck"
    @moon_android.Gate::Check => "Check"
    @moon_android.Gate::CheckDenyWarn => "CheckDenyWarn"
    @moon_android.Gate::TestCoverage => "TestCoverage"
    @moon_android.Gate::Bench => "Bench"
    @moon_android.Gate::InfoSnapshot => "InfoSnapshot"
    @moon_android.Gate::VersionLock => "VersionLock"
  }
}

///|
/// 内部助手：逗号分隔（空段保留，交由下游校验拒绝）。
fn split_comma(s : String) -> Array[String] {
  let out : Array[String] = []
  let chars = s.to_array()
  let mut start = 0
  let mut i = 0
  while i <= chars.length() {
    if i == chars.length() || chars[i] == ',' {
      out.push(s[start:i].to_owned())
      start = i + 1
    }
    i = i + 1
  }
  out
}

///|
/// 内部助手：十进制整数解析（可选负号；非法 → None）。
fn parse_int32(s : String) -> Int32? {
  let chars = s.to_array()
  let n = chars.length()
  if n == 0 {
    return None
  }
  let mut i = 0
  let mut negative = false
  if chars[0] == '-' {
    negative = true
    i = 1
  }
  if i >= n {
    return None
  }
  let mut value : Int32 = 0
  let mut digits = 0
  while i < n {
    let c = chars[i]
    if c < '0' || c > '9' {
      return None
    }
    digits = digits + 1
    if digits > 9 {
      return None
    }
    value = value * 10 + (c.to_int() - '0'.to_int())
    i = i + 1
  }
  Some(if negative { -value } else { value })
}

///|
/// flag 解析结果（缺省值即演示配置）。
struct Flags {
  mut package_id : String
  mut abis : String
  mut min_sdk : String
  mut target_sdk : String
  mut schemes : String
  mut keystore_ref : String
  mut activity : String
  mut entry_url : String
  mut profile : String
  mut app_name : String
  mut required_major : String
  mut java_home : String?
  mut java_version : String?
  mut existing : String
  mut strict : Bool
}

///|
/// 默认 flags。
fn default_flags() -> Flags {
  {
    package_id: "com.example.app",
    abis: "arm64-v8a",
    min_sdk: "24",
    target_sdk: "34",
    schemes: "V2,V3",
    keystore_ref: "@keys/release.jks",
    activity: "webview",
    entry_url: "https://example.com/index.html",
    profile: "debug",
    app_name: "Demo App",
    required_major: "17",
    java_home: None,
    java_version: None,
    existing: "",
    strict: false,
  }
}

///|
/// 内部助手：解析 flags；用法错误 → None（调用方退出码 2）。
fn parse_flags(args : Array[String]) -> Flags? {
  let flags = default_flags()
  let mut i = 0
  while i < args.length() {
    let arg = args[i]
    if arg == "--strict" {
      flags.strict = true
      i = i + 1
      continue
    }
    if !arg.has_prefix("--") {
      return None
    }
    if i + 1 >= args.length() {
      return None
    }
    let value = args[i + 1]
    match arg {
      "--package" => flags.package_id = value
      "--abis" => flags.abis = value
      "--min-sdk" => flags.min_sdk = value
      "--target-sdk" => flags.target_sdk = value
      "--schemes" => flags.schemes = value
      "--keystore-ref" => flags.keystore_ref = value
      "--activity" => flags.activity = value
      "--entry-url" => flags.entry_url = value
      "--profile" => flags.profile = value
      "--app-name" => flags.app_name = value
      "--required-major" => flags.required_major = value
      "--java-home" => flags.java_home = Some(value)
      "--java-version" => flags.java_version = Some(value)
      "--existing" => flags.existing = value
      _ => return None
    }
    i = i + 2
  }
  Some(flags)
}

///|
/// 内部助手：flags → BuildConfig；用法错误 → None，库校验错误照常 raise。
fn build_config(
  flags : Flags,
) -> @moon_android.BuildConfig? raise @moon_android.MoonAndroidError {
  let min_sdk = match parse_int32(flags.min_sdk) {
    Some(v) => v
    None => return None
  }
  let target_sdk = match parse_int32(flags.target_sdk) {
    Some(v) => v
    None => return None
  }
  let abis : Array[@moon_android.Abi] = []
  for name in split_comma(flags.abis) {
    abis.push(@moon_android.parse_abi_dir_name(name))
  }
  let schemes : Array[@moon_android.SigningScheme] = []
  for name in split_comma(flags.schemes) {
    match name {
      "V1" => schemes.push(@moon_android.SigningScheme::V1)
      "V2" => schemes.push(@moon_android.SigningScheme::V2)
      "V3" => schemes.push(@moon_android.SigningScheme::V3)
      "V31" => schemes.push(@moon_android.SigningScheme::V31)
      _ => return None
    }
  }
  let activity = match flags.activity {
    "webview" => @moon_android.ActivityKind::WebView
    "gles" => @moon_android.ActivityKind::GlesSurface
    "native" => @moon_android.ActivityKind::NativeOnly
    _ => return None
  }
  let profile = match flags.profile {
    "debug" => @moon_android.BuildProfile::Debug
    "release" => @moon_android.BuildProfile::Release
    _ => return None
  }
  Some({
    package_id: { name: flags.package_id, },
    activity,
    entry_url: Some(flags.entry_url),
    abis,
    min_sdk,
    target_sdk,
    signing_schemes: schemes,
    keystore_ref: flags.keystore_ref,
    profile,
    toolchain: locked_toolchain(),
    extra_native_libs: [],
  })
}

///|
/// gates 子命令：建议门禁序列（7 行）。
fn cmd_gates() -> Int32 {
  for gate in @moon_android.ci_gate_plan() {
    println(gate_label(gate))
  }
  0
}

///|
/// render 子命令：渲染十步计划脚本。
fn cmd_render(flags : Flags) -> Int32 {
  let config_result = build_config(flags) catch { e => return library_error(e) }
  let config = match config_result {
    Some(c) => c
    None =>
      return usage_error(
        "flag 取值非法（SDK 整数 / ABI / 签名 / 壳 / 剖面）",
      )
  }
  let plan = @moon_android.plan_build(config, []) catch {
    e => return library_error(e)
  }
  let text = @moon_android.render_script(plan) catch {
    e => return library_error(e)
  }
  println(text)
  0
}

///|
/// template 子命令：渲染模板四阶段脚本（零资产 / 零模块依赖演示）。
fn cmd_template(flags : Flags) -> Int32 {
  let config_result = build_config(flags) catch { e => return library_error(e) }
  let config = match config_result {
    Some(c) => c
    None =>
      return usage_error(
        "flag 取值非法（SDK 整数 / ABI / 签名 / 壳 / 剖面）",
      )
  }
  let params : @moon_android.TemplateParams = {
    config,
    app_name: flags.app_name,
    module_deps: [],
    assets: [],
  }
  let tree = @moon_android.plan_template(params) catch {
    e => return library_error(e)
  }
  let text = @moon_android.render_template_script(tree) catch {
    e => return library_error(e)
  }
  println(text)
  0
}

///|
/// probe-jdk 子命令：纯评估探测报告（stdout），JdkFound → 0，否则 1。
fn cmd_probe_jdk(flags : Flags) -> Int32 {
  let required = match parse_int32(flags.required_major) {
    Some(v) => v
    None => return usage_error("--required-major 需为整数")
  }
  let java_home : @moon_android.JdkEntry? = match flags.java_home {
    Some(path) => Some({ path, version: flags.java_version, })
    None => None
  }
  let existing : Array[String] = if flags.existing == "" {
    []
  } else {
    split_comma(flags.existing)
  }
  let env : @moon_android.JdkProbeEnv = {
    java_home,
    registry_entries: [],
    common_entries: [],
    path_entries: [],
    existing_jdk_dirs: existing,
    required_major: required,
  }
  let result = if flags.strict {
    @moon_android.probe_jdk_strict(env) catch {
      e => return library_error(e)
    }
  } else {
    @moon_android.probe_jdk(env) catch {
      e => return library_error(e)
    }
  }
  let status = match result.status {
    @moon_android.JdkProbeStatus::JdkFound => "JdkFound"
    @moon_android.JdkProbeStatus::JdkNotFound => "JdkNotFound"
    @moon_android.JdkProbeStatus::JdkVersionUnmatched => "JdkVersionUnmatched"
  }
  println("status: " + status)
  match result.selected {
    Some(c) => println("selected: " + c.path)
    None => println("selected: (none)")
  }
  for message in result.diagnostics {
    println("diag: " + message)
  }
  if result.status is @moon_android.JdkProbeStatus::JdkFound {
    0
  } else {
    1
  }
}

///|
/// 内部助手：库错误 → stderr 变体名 + 退出码 1。
fn library_error(e : Error) -> Int32 {
  eprintln("error: " + error_variant(e))
  1
}

///|
/// 内部助手：用法错误 → stderr 提示 + 退出码 2。
fn usage_error(msg : String) -> Int32 {
  eprintln("error: " + msg)
  eprintln("运行 \{tool_name} --help 查看用法")
  2
}

///|
/// 运行入口：返回进程退出码（args[0] 为程序名）。
fn run(args : Array[String]) -> Int32 {
  if args.length() <= 1 {
    return usage_error(
      "缺少子命令（gates / render / template / probe-jdk）",
    )
  }
  let sub = args[1]
  if sub == "--help" || sub == "-h" || sub == "help" {
    println(usage_text())
    return 0
  }
  let flags = match parse_flags(args[2:].to_owned()) {
    Some(f) => f
    None => return usage_error("未知 flag 或缺少取值")
  }
  match sub {
    "gates" => cmd_gates()
    "render" => cmd_render(flags)
    "template" => cmd_template(flags)
    "probe-jdk" => cmd_probe_jdk(flags)
    _ => usage_error("未知子命令：" + sub)
  }
}

///|
fn main {
  let code = run(@env.args())
  if code != 0 {
    @env.exit(code)
  }
}
