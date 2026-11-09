///|
/// MoonBit → Android 的 APK 打包链「计划与配置」契约。
///
/// 边界：本库只描述构建计划、工具链版本与门禁，**不执行**任何外部命令、
/// 不读写 APK、不签名、不调用 adb、不实现 Gradle/IDE 集成。
/// 本文件包含数据结构定义与 4 个纯函数实现（plan_build / render_script /
/// verify_artifact / ci_gate_plan）及其内部校验助手；全部为纯计算、
/// 确定性、无 I/O、可并发调用。

///|
/// 应用包名（Android package id）。
pub(all) struct PackageId {
  name : String
}

///|
/// 壳 Activity 模板种类。
pub(all) enum ActivityKind {
  WebView
  GlesSurface
  NativeOnly
}

///|
/// 签名方案组合（按 minSdk / targetSdk 决定；v1 用于兼容旧机）。
pub(all) enum SigningScheme {
  V1
  V2
  V3
  V31
}

///|
/// 构建 Profile：debug / release 与优化级别。
pub(all) enum BuildProfile {
  Debug
  Release
}

///|
/// 目标 ABI。
pub(all) enum Abi {
  ArmeabiV7a
  Arm64V8a
  X86
  X86_64
}

///|
/// 外部工具链版本锁定。任一字段为空即视为未锁定，CI 必须拒绝。
pub(all) struct ToolchainVersions {
  moon_cli : String
  moonc : String
  core : String
  ndk : String
  build_tools : String
  platform : String
  jdk : String
  cmake : String?
}

///|
/// 构建配置。密钥只以引用形式出现，绝不内嵌密钥材料。
pub(all) struct BuildConfig {
  package_id : PackageId
  activity : ActivityKind
  entry_url : String?
  abis : Array[Abi]
  min_sdk : Int32
  target_sdk : Int32
  signing_schemes : Array[SigningScheme]
  keystore_ref : String
  profile : BuildProfile
  toolchain : ToolchainVersions
  extra_native_libs : Array[String]
}

///|
/// 有序构建步骤。顺序约束：`Zipalign` 必须在 `Apksigner` 之前。
pub(all) enum BuildStep {
  CrossCompile
  Aapt2Compile
  Aapt2Link
  Javac
  D8
  Assemble
  Zipalign
  Apksigner
  Verify
  AdbInstall
}

///|
/// 构建计划：步骤序列 + 每步输入/输出产物名。纯数据，不含可执行动作。
pub(all) struct BuildPlan {
  steps : Array[BuildStep]
  inputs : Array[String]
  outputs : Array[String]
  config : BuildConfig
}

///|
/// 产物校验结果。
pub(all) struct Artifact {
  path : String
  size_bytes : UInt64
  sha256 : String
  abis : Array[Abi]
  signatures : Array[SigningScheme]
}

///|
/// CI 门禁项。
#derive(Debug)
pub(all) enum Gate {
  FmtCheck
  Check
  CheckDenyWarn
  TestCoverage
  Bench
  InfoSnapshot
  VersionLock
}

///|
pub extend Gate with Debug::{to_repr}

///|
/// 打包链错误模型。
#derive(Debug)
pub suberror MoonAndroidError {
  InvalidPackage(String)
  UnsupportedAbi(String)
  MissingTool(String)
  ToolchainNotLocked(String)
  InvalidStepOrder(String, String)
  KeyMaterialEmbedded
  SigningSchemeConflict(String)
  ArtifactMismatch(String)
  MissingGate(Gate)
}

///|
pub extend MoonAndroidError with Debug::{to_repr}

///|
/// 构建计划契约：实现必须是确定性的、可复现的，且不产生副作用。
pub trait BuildPlanner {
  fn plan(Self) -> BuildPlan raise MoonAndroidError
}

///|
/// 内部助手：构建步骤的规范秩。规范全序为
/// `CrossCompile(0) → Aapt2Compile(1) → Aapt2Link(2) → Javac(3) → D8(4) → Assemble(5)`
/// `→ Zipalign(6) → Apksigner(7) → Verify(8) → AdbInstall(9)`。
fn step_rank(step : BuildStep) -> Int32 {
  match step {
    CrossCompile => 0
    Aapt2Compile => 1
    Aapt2Link => 2
    Javac => 3
    D8 => 4
    Assemble => 5
    Zipalign => 6
    Apksigner => 7
    Verify => 8
    AdbInstall => 9
  }
}

///|
/// 内部助手：步骤的稳定名称（用于脚本文本与错误负载）。
fn step_name(step : BuildStep) -> String {
  match step {
    CrossCompile => "CrossCompile"
    Aapt2Compile => "Aapt2Compile"
    Aapt2Link => "Aapt2Link"
    Javac => "Javac"
    D8 => "D8"
    Assemble => "Assemble"
    Zipalign => "Zipalign"
    Apksigner => "Apksigner"
    Verify => "Verify"
    AdbInstall => "AdbInstall"
  }
}

///|
/// 内部助手：ABI 的 Android 目录名。
fn abi_name(abi : Abi) -> String {
  match abi {
    ArmeabiV7a => "armeabi-v7a"
    Arm64V8a => "arm64-v8a"
    X86 => "x86"
    X86_64 => "x86_64"
  }
}

///|
/// 内部助手：签名方案名。
fn signing_scheme_name(scheme : SigningScheme) -> String {
  match scheme {
    V1 => "V1"
    V2 => "V2"
    V3 => "V3"
    V31 => "V31"
  }
}

///|
/// 内部助手：壳 Activity 名。
fn activity_name(activity : ActivityKind) -> String {
  match activity {
    WebView => "WebView"
    GlesSurface => "GlesSurface"
    NativeOnly => "NativeOnly"
  }
}

///|
/// 内部助手：构建 Profile 名。
fn profile_name(profile : BuildProfile) -> String {
  match profile {
    BuildProfile::Debug => "debug"
    BuildProfile::Release => "release"
  }
}

///|
/// 内部助手：ASCII 字母判定。
fn is_ascii_letter(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
}

///|
/// 内部助手：包名段合法字符判定（字母开头，其余 [A-Za-z0-9_]）。
fn is_name_char(c : Char) -> Bool {
  is_ascii_letter(c) || (c >= '0' && c <= '9') || c == '_'
}

///|
/// 内部助手：校验一个点分段：非空、字母开头、其余为 [A-Za-z0-9_]。
fn valid_segment(chars : Array[Char], start : Int32, fin : Int32) -> Bool {
  if start >= fin {
    return false
  }
  if !is_ascii_letter(chars[start]) {
    return false
  }
  for i in (start + 1)..<fin {
    if !is_name_char(chars[i]) {
      return false
    }
  }
  true
}

///|
/// 内部助手：Android 包名规则——至少两个点分段；每段非空、以 ASCII 字母
/// 开头，其余字符为 [A-Za-z0-9_]。违反即 `InvalidPackage`。
fn valid_package_name(name : String) -> Bool {
  if name.is_empty() {
    return false
  }
  let chars = name.to_array()
  let mut seg_start = 0
  let mut seg_count = 1
  let mut valid = true
  for i in 0..<chars.length() {
    if chars[i] == '.' {
      if !valid_segment(chars, seg_start, i) {
        valid = false
      }
      seg_start = i + 1
      seg_count = seg_count + 1
    }
  }
  if !valid_segment(chars, seg_start, chars.length()) {
    valid = false
  }
  valid && seg_count >= 2
}

///|
/// 内部助手：`keystore_ref` 是否混入了密钥材料或内联凭据。
/// 检测信号：PEM 头（`-----BEGIN`）、`private key`、`storepass`、`keypass`、
/// `password`、内联 base64 数据（`base64,`）。命中即 `KeyMaterialEmbedded`。
fn looks_like_key_material(ref_ : String) -> Bool {
  let lower = ref_.to_lower()
  lower.contains("-----begin") ||
  lower.contains("private key") ||
  lower.contains("storepass") ||
  lower.contains("keypass") ||
  lower.contains("password") ||
  lower.contains("base64,")
}

///|
/// 内部助手：返回第一个为空的必锁版本字段（moon_cli / moonc / core / ndk /
/// build_tools / platform / jdk）。cmake 为可选项，缺失由 `MissingTool` 报告。
fn first_unlocked_field(tv : ToolchainVersions) -> String? {
  if tv.moon_cli == "" {
    return Some("moon_cli")
  }
  if tv.moonc == "" {
    return Some("moonc")
  }
  if tv.core == "" {
    return Some("core")
  }
  if tv.ndk == "" {
    return Some("ndk")
  }
  if tv.build_tools == "" {
    return Some("build_tools")
  }
  if tv.platform == "" {
    return Some("platform")
  }
  if tv.jdk == "" {
    return Some("jdk")
  }
  None
}

///|
/// 内部助手：每步所需的工具名（顺序稳定）。
fn tools_of_step(step : BuildStep) -> Array[String] {
  match step {
    CrossCompile => ["cmake", "ndk"]
    Aapt2Compile => ["aapt2"]
    Aapt2Link => ["aapt2", "android.jar"]
    Javac => ["javac", "android.jar"]
    D8 => ["d8"]
    Assemble => ["jar"]
    Zipalign => ["zipalign"]
    Apksigner => ["apksigner"]
    Verify => ["apksigner"]
    AdbInstall => ["adb"]
  }
}

///|
/// 内部助手：工具 → 版本锁来源。`adb` 属设备侧工具，不在
/// `ToolchainVersions` 锁定范围内，视为恒可用；其余工具由对应字段供版本，
/// 字段为空即缺失（`MissingTool`）。
fn tool_version(tool : String, tv : ToolchainVersions) -> String? {
  if tool == "adb" {
    return Some("device-side")
  }
  if tool == "cmake" {
    if tv.cmake is Some(v) && v != "" {
      return Some(v)
    } else {
      return None
    }
  }
  let field = if tool == "ndk" {
    tv.ndk
  } else if tool == "aapt2" ||
    tool == "d8" ||
    tool == "zipalign" ||
    tool == "apksigner" {
    tv.build_tools
  } else if tool == "javac" || tool == "jar" {
    tv.jdk
  } else {
    tv.platform // android.jar
  }
  if field == "" {
    None
  } else {
    Some(field)
  }
}

///|
/// 内部助手：校验步骤序列满足规范全序（严格递增秩；重复步骤按
/// `InvalidStepOrder(name, name)` 拒绝）。
fn validate_step_order(steps : Array[BuildStep]) -> Unit raise MoonAndroidError {
  for i in 0..<steps.length() {
    for j in (i + 1)..<steps.length() {
      if step_rank(steps[i]) >= step_rank(steps[j]) {
        raise InvalidStepOrder(step_name(steps[i]), step_name(steps[j]))
      }
    }
  }
}

///|
/// 内部助手：计划所需的每个工具都必须能从 `ToolchainVersions` 解析到版本。
fn validate_tools(
  steps : Array[BuildStep],
  tv : ToolchainVersions,
) -> Unit raise MoonAndroidError {
  for step in steps {
    for tool in tools_of_step(step) {
      if tool_version(tool, tv) is None {
        raise MissingTool(tool)
      }
    }
  }
}

///|
/// 内部助手：签名方案集合合法性。空集合、重复、`min_sdk < 24` 缺 V1、
/// V31 缺 V3 均为 `SigningSchemeConflict`。
fn validate_signing(config : BuildConfig) -> Unit raise MoonAndroidError {
  let schemes = config.signing_schemes
  if schemes.length() == 0 {
    raise SigningSchemeConflict(
      "signing_schemes 为空：至少需要启用一种签名方案",
    )
  }
  for i in 0..<schemes.length() {
    for j in (i + 1)..<schemes.length() {
      if signing_scheme_name(schemes[i]) == signing_scheme_name(schemes[j]) {
        raise SigningSchemeConflict(
          "重复的签名方案：" + signing_scheme_name(schemes[i]),
        )
      }
    }
  }
  if config.min_sdk < 24 && !has_scheme(schemes, "V1") {
    raise SigningSchemeConflict(
      "min_sdk < 24 时必须启用 V1：低版本设备无法校验 v2+ 签名",
    )
  }
  if has_scheme(schemes, "V31") && !has_scheme(schemes, "V3") {
    raise SigningSchemeConflict(
      "V31（密钥轮换）必须与 V3 一同启用",
    )
  }
}

///|
/// 内部助手：签名方案集合中是否包含指定名。
fn has_scheme(schemes : Array[SigningScheme], want : String) -> Bool {
  for scheme in schemes {
    if signing_scheme_name(scheme) == want {
      return true
    }
  }
  false
}

///|
/// 内部助手：ABI 集合合法性。空集合或重复均为 `UnsupportedAbi`
/// （空集合报 `UnsupportedAbi("none")`）。
fn validate_abis(abis : Array[Abi]) -> Unit raise MoonAndroidError {
  if abis.length() == 0 {
    raise UnsupportedAbi("none")
  }
  for i in 0..<abis.length() {
    for j in (i + 1)..<abis.length() {
      if abi_name(abis[i]) == abi_name(abis[j]) {
        raise UnsupportedAbi(abi_name(abis[i]))
      }
    }
  }
}

///|
/// 内部助手：规范 10 步序列（固定顺序）。
fn canonical_steps() -> Array[BuildStep] {
  [
    CrossCompile,
    Aapt2Compile,
    Aapt2Link,
    Javac,
    D8,
    Assemble,
    Zipalign,
    Apksigner,
    Verify,
    AdbInstall,
  ]
}

///|
/// 内部助手：产物基名 = 包名。
fn artifact_base(config : BuildConfig) -> String {
  config.package_id.name
}

///|
/// 内部助手：C stub 的 so 名（取包名最后一段），如 `com.example.app` → `libapp.so`。
fn soname(config : BuildConfig) -> String {
  let name = config.package_id.name
  let chars = name.to_array()
  let mut start = 0
  for i in 0..<chars.length() {
    if chars[i] == '.' {
      start = i + 1
    }
  }
  "lib" + name[start:].to_owned() + ".so"
}

///|
/// 内部助手：每步的主输入产物名。
fn step_input(step : BuildStep, config : BuildConfig) -> String {
  let base = artifact_base(config)
  match step {
    CrossCompile => "src/native/stub.c"
    Aapt2Compile => "res/"
    Aapt2Link => base + ".flat"
    Javac => "gen/"
    D8 => base + ".classes"
    Assemble => "classes.dex"
    Zipalign => base + "-unsigned.apk"
    Apksigner => base + "-aligned.apk"
    Verify => base + ".apk"
    AdbInstall => base + ".apk"
  }
}

///|
/// 内部助手：每步的主输出产物名。`Apksigner` 的输出即最终签名 APK。
fn step_output(step : BuildStep, config : BuildConfig) -> String {
  let base = artifact_base(config)
  match step {
    CrossCompile => soname(config)
    Aapt2Compile => base + ".flat"
    Aapt2Link => base + ".res.apk"
    Javac => base + ".classes"
    D8 => "classes.dex"
    Assemble => base + "-unsigned.apk"
    Zipalign => base + "-aligned.apk"
    Apksigner => base + ".apk"
    Verify => base + ".verify.txt"
    AdbInstall => "device/" + base + ".apk"
  }
}

///|
/// 内部助手：数组拼接为 `, ` 分隔文本。
fn join_comma(items : Array[String]) -> String {
  let mut out = ""
  for i in 0..<items.length() {
    if i > 0 {
      out = out + ", "
    }
    out = out + items[i]
  }
  out
}

///|
/// 内部助手：步骤所需工具的 `名@版本` 描述行。
fn tool_line(step : BuildStep, tv : ToolchainVersions) -> String {
  let parts : Array[String] = []
  for tool in tools_of_step(step) {
    let version = match tool_version(tool, tv) {
      Some(v) => v
      None => "(missing)"
    }
    parts.push(tool + "@" + version)
  }
  join_comma(parts)
}

///|
/// 内部助手：`sha256` 值规格——恰为 64 位十六进制字符。
fn is_sha256_hex(s : String) -> Bool {
  if s.length() != 64 {
    return false
  }
  for c in s.to_array() {
    let hex = (c >= '0' && c <= '9') ||
      (c >= 'a' && c <= 'f') ||
      (c >= 'A' && c <= 'F')
    if !hex {
      return false
    }
  }
  true
}

///|
/// 内部助手：ABI 多重集合相等（计数比对，与顺序无关）。
fn same_abi_multiset(a : Array[Abi], b : Array[Abi]) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for x in a {
    let mut ca = 0
    let mut cb = 0
    for y in a {
      if abi_name(x) == abi_name(y) {
        ca = ca + 1
      }
    }
    for y in b {
      if abi_name(x) == abi_name(y) {
        cb = cb + 1
      }
    }
    if ca != cb {
      return false
    }
  }
  true
}

///|
/// 内部助手：签名方案多重集合相等（计数比对，与顺序无关）。
fn same_scheme_multiset(
  a : Array[SigningScheme],
  b : Array[SigningScheme],
) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for x in a {
    let mut ca = 0
    let mut cb = 0
    for y in a {
      if signing_scheme_name(x) == signing_scheme_name(y) {
        ca = ca + 1
      }
    }
    for y in b {
      if signing_scheme_name(x) == signing_scheme_name(y) {
        cb = cb + 1
      }
    }
    if ca != cb {
      return false
    }
  }
  true
}

///|
/// 内部助手：每步的命令行模板文本（仅供审阅，绝不执行）。
/// 命令引用 `$CMAKE` / `$AAPT2` / `$JAVAC` / `$D8` / `$JAR` / `$ZIPALIGN` /
/// `$APKSIGNER` / `$ADB` / `$NDK_ROOT` / `$ANDROID_JAR` / `$KEYSTORE_REF`
/// 等环境变量，由组合根在真正执行时解析；keystore 只以 `$KEYSTORE_REF`
/// 引用出现，脚本文本不包含任何密钥材料。
fn command_lines(
  step : BuildStep,
  config : BuildConfig,
  in_name : String,
  out_name : String,
) -> String {
  let tv = config.toolchain
  match step {
    CrossCompile => {
      let mut out = ""
      for abi in config.abis {
        out = out +
          "$CMAKE -S src/native -B out/native/" +
          abi_name(abi) +
          " -DANDROID_ABI=" +
          abi_name(abi) +
          " -DANDROID_PLATFORM=" +
          tv.platform +
          " -DCMAKE_TOOLCHAIN_FILE=$NDK_ROOT/build/cmake/android.toolchain.cmake\n"
        out = out +
          "$CMAKE --build out/native/" +
          abi_name(abi) +
          " --target " +
          soname(config) +
          "\n"
      }
      out
    }
    Aapt2Compile => "$AAPT2 compile --dir res -o " + out_name + "\n"
    Aapt2Link =>
      "$AAPT2 link -o " +
      out_name +
      " -I $ANDROID_JAR --manifest AndroidManifest.xml " +
      in_name +
      "\n"
    Javac =>
      "$JAVAC -classpath $ANDROID_JAR -d " +
      out_name +
      " gen/*.java src/java/*.java\n"
    D8 => {
      let mode = if config.profile is BuildProfile::Debug {
        "--debug"
      } else {
        "--release"
      }
      "$D8 " +
      mode +
      " --min-api \{config.min_sdk} --output " +
      out_name +
      " " +
      in_name +
      "\n"
    }
    Assemble => {
      let base = artifact_base(config)
      let mut out = "cp " +
        base +
        ".res.apk " +
        out_name +
        " && $JAR uf " +
        out_name +
        " " +
        in_name +
        "\n"
      for abi in config.abis {
        out = out +
          "$JAR uf " +
          out_name +
          " -C out/native/" +
          abi_name(abi) +
          " " +
          soname(config) +
          "\n"
      }
      out
    }
    Zipalign => "$ZIPALIGN -p -f 4 " + in_name + " " + out_name + "\n"
    Apksigner => {
      let mut flags = ""
      for scheme in config.signing_schemes {
        let name = signing_scheme_name(scheme)
        let flag = if name == "V31" {
          "--v31-signing-enabled"
        } else {
          "--v" + name[1:].to_owned() + "-signing-enabled"
        }
        flags = flags + " " + flag + " true"
      }
      "$APKSIGNER sign --ks \"$KEYSTORE_REF\"" +
      flags +
      " --out " +
      out_name +
      " " +
      in_name +
      "\n"
    }
    Verify =>
      "$APKSIGNER verify --print-certs " + in_name + " > " + out_name + "\n"
    AdbInstall => "$ADB install -r " + in_name + "\n"
  }
}

///|
/// 生成构建计划（纯计算，不执行）。
///
/// - 参数：`config` 为只读配置；`abis` 为空时由配置中的 `abis` 决定，
///   非空时覆盖 `config.abis`（生效 ABI 集记录在 `plan.config.abis`）。
/// - 返回：`BuildPlan` 纯值，步骤为规范 10 步且顺序已校验
///   （zipalign 早于 apksigner）；`inputs` / `outputs` 与 `steps` 等长对齐。
/// - 错误（按校验次序）：`InvalidPackage`（包名非法）、`ToolchainNotLocked`
///   （7 个必锁版本字段任一为空）、`KeyMaterialEmbedded`（keystore_ref 内嵌
///   密钥材料）、`SigningSchemeConflict`（空/重复方案、min_sdk<24 缺 V1、
///   V31 缺 V3）、`UnsupportedAbi`（ABI 集为空或重复）、`MissingTool`
///   （如 CrossCompile 需要 cmake 而 toolchain.cmake 缺失）、
///   `InvalidStepOrder`（步骤序列违反规范全序）。
/// - 线程：纯函数，无状态，可并发调用。
/// - 非目标：不执行脚本、不签名、不做设备交互、不实现 Gradle。
pub fn plan_build(
  config : BuildConfig,
  abis : Array[Abi],
) -> BuildPlan raise MoonAndroidError {
  if !valid_package_name(config.package_id.name) {
    raise InvalidPackage(config.package_id.name)
  }
  if first_unlocked_field(config.toolchain) is Some(field) {
    raise ToolchainNotLocked(field)
  }
  if looks_like_key_material(config.keystore_ref) {
    raise KeyMaterialEmbedded
  }
  validate_signing(config)
  let effective_abis = if abis.length() == 0 { config.abis } else { abis }
  validate_abis(effective_abis)
  let steps = canonical_steps()
  validate_step_order(steps)
  validate_tools(steps, config.toolchain)
  let inputs : Array[String] = []
  let outputs : Array[String] = []
  for step in steps {
    inputs.push(step_input(step, config))
    outputs.push(step_output(step, config))
  }
  let effective_config : BuildConfig = {
    package_id: config.package_id,
    activity: config.activity,
    entry_url: config.entry_url,
    abis: effective_abis,
    min_sdk: config.min_sdk,
    target_sdk: config.target_sdk,
    signing_schemes: config.signing_schemes,
    keystore_ref: config.keystore_ref,
    profile: config.profile,
    toolchain: config.toolchain,
    extra_native_libs: config.extra_native_libs,
  }
  { steps, inputs, outputs, config: effective_config, }
}

///|
/// 把构建计划渲染为可审阅的脚本文本（仍不执行）。
///
/// - 确定性：同输入两次渲染逐字相等；输出只由 `plan` 值决定。
/// - 错误：`InvalidStepOrder`（步骤序列违反规范全序）、`MissingTool`
///   （步骤所需工具在 `plan.config.toolchain` 中缺失）；
///   为防密钥泄漏，`keystore_ref` 内嵌密钥材料时额外以
///   `KeyMaterialEmbedded` 拒绝渲染（安全优先于渲染宽容度）。
/// - 非目标：不 spawn 进程、不读写文件。
pub fn render_script(plan : BuildPlan) -> String raise MoonAndroidError {
  let config = plan.config
  if looks_like_key_material(config.keystore_ref) {
    raise KeyMaterialEmbedded
  }
  validate_step_order(plan.steps)
  validate_tools(plan.steps, config.toolchain)
  let tv = config.toolchain
  let base = artifact_base(config)
  let abi_names : Array[String] = []
  for abi in config.abis {
    abi_names.push(abi_name(abi))
  }
  let scheme_names : Array[String] = []
  for scheme in config.signing_schemes {
    scheme_names.push(signing_scheme_name(scheme))
  }
  let mut text = ""
  text = text + "#!/bin/sh\n"
  text = text +
    "# rendered by moon_android::render_script — deterministic review artifact; DO NOT EXECUTE\n"
  text = text + "# package_id: " + base + "\n"
  text = text + "# activity: " + activity_name(config.activity) + "\n"
  text = text +
    "# entry_url: " +
    (if config.entry_url is Some(url) { url } else { "(none)" }) +
    "\n"
  text = text + "# profile: " + profile_name(config.profile) + "\n"
  text = text + "# min_sdk: \{config.min_sdk}\n"
  text = text + "# target_sdk: \{config.target_sdk}\n"
  text = text + "# abis: " + join_comma(abi_names) + "\n"
  text = text + "# signing_schemes: " + join_comma(scheme_names) + "\n"
  text = text + "# keystore_ref: " + config.keystore_ref + "\n"
  text = text + "# toolchain.moon_cli: " + tv.moon_cli + "\n"
  text = text + "# toolchain.moonc: " + tv.moonc + "\n"
  text = text + "# toolchain.core: " + tv.core + "\n"
  text = text + "# toolchain.ndk: " + tv.ndk + "\n"
  text = text + "# toolchain.build_tools: " + tv.build_tools + "\n"
  text = text + "# toolchain.platform: " + tv.platform + "\n"
  text = text + "# toolchain.jdk: " + tv.jdk + "\n"
  text = text +
    "# toolchain.cmake: " +
    (if tv.cmake is Some(v) { v } else { "(unlocked)" }) +
    "\n"
  text = text +
    "# step order contract: CrossCompile -> Aapt2Compile -> Aapt2Link -> Javac -> D8\n"
  text = text +
    "#   -> Assemble -> Zipalign -> Apksigner -> Verify -> AdbInstall\n"
  let total = plan.steps.length()
  for i in 0..<total {
    let step = plan.steps[i]
    let in_name = if i < plan.inputs.length() {
      plan.inputs[i]
    } else {
      "(unspecified)"
    }
    let out_name = if i < plan.outputs.length() {
      plan.outputs[i]
    } else {
      "(unspecified)"
    }
    text = text + "\n# [\{i + 1}/\{total}] " + step_name(step) + "\n"
    text = text + "#   in: " + in_name + " -> out: " + out_name + "\n"
    text = text + "#   tools: " + tool_line(step, tv) + "\n"
    text = text + command_lines(step, config, in_name, out_name)
  }
  text = text +
    "\n# end of plan: \{total} steps; moon_android never executes this script\n"
  text
}

///|
/// 校验产物元数据（大小、ABI、签名方案、哈希）是否与计划一致。
///
/// - 结构性不可接受的元数据以 `ArtifactMismatch` 拒绝：产物路径与
///   `Apksigner` 步骤产物名不符、`size_bytes` 为 0、`sha256` 非 64 位
///   十六进制、ABI/签名方案集合为空、计划缺少 `Apksigner` 步骤或产物名。
/// - 可判定的值比对返回 `Bool`：`true` 当且仅当产物的 ABI 多重集合与
///   `plan.config.abis` 相等、签名方案多重集合与 `plan.config.signing_schemes`
///   相等；否则 `false`（产物元数据与计划不完全一致）。
/// - 本库不读文件、不算哈希；`sha256` 由组合根填入后仅做值规格与集合比对。
pub fn verify_artifact(
  plan : BuildPlan,
  artifact : Artifact,
) -> Bool raise MoonAndroidError {
  let steps = plan.steps
  let mut signer_index = -1
  for i in 0..<steps.length() {
    if steps[i] is Apksigner {
      signer_index = i
    }
  }
  if signer_index < 0 {
    raise ArtifactMismatch(
      "计划缺少 Apksigner 步骤：无法确定最终 APK 产物",
    )
  }
  if signer_index >= plan.outputs.length() {
    raise ArtifactMismatch(
      "计划缺少 Apksigner 步骤的产物名（outputs 不完整）",
    )
  }
  let expected = plan.outputs[signer_index]
  if artifact.path != expected {
    raise ArtifactMismatch(
      "产物路径与计划不符：期望 " +
      expected +
      "，实际 " +
      artifact.path,
    )
  }
  if artifact.size_bytes == 0UL {
    raise ArtifactMismatch("产物为空：size_bytes = 0")
  }
  if !is_sha256_hex(artifact.sha256) {
    raise ArtifactMismatch(
      "sha256 缺失或格式非法（需恰为 64 位十六进制字符）",
    )
  }
  if artifact.abis.length() == 0 {
    raise ArtifactMismatch("产物未记录任何 ABI")
  }
  if artifact.signatures.length() == 0 {
    raise ArtifactMismatch("产物未记录任何签名方案")
  }
  same_abi_multiset(artifact.abis, plan.config.abis) &&
  same_scheme_multiset(artifact.signatures, plan.config.signing_schemes)
}

///|
/// 返回本项目建议的 CI 门禁序列（纯常量、确定性、可并发）。
///
/// 顺序：`FmtCheck → Check → CheckDenyWarn → TestCoverage → Bench →
/// InfoSnapshot → VersionLock`。`CheckDenyWarn` 在建议序列中并作硬门禁
/// 执行（实现完成后 0068 归零，早期实现未完成阶段的临时豁免已失效）。
pub fn ci_gate_plan() -> Array[Gate] {
  [
    Gate::FmtCheck,
    Gate::Check,
    Gate::CheckDenyWarn,
    Gate::TestCoverage,
    Gate::Bench,
    Gate::InfoSnapshot,
    Gate::VersionLock,
  ]
}
