///|
/// Windows JDK 探测：**纯评估器**。
///
/// 边界：本库零 I/O（`preferred_target = "wasm"`），不读环境变量、不读注册表、
/// 不访问文件系统。探测拆成两段：
///
/// 1. **采集器（组合根）**：读取 `JAVA_HOME`、注册表
///    `HKLM\SOFTWARE\JavaSoft\JDK\<ver>\JavaHome`（含 32 位视图
///    `WOW6432Node`）、常见安装根目录与 `PATH`，并验证候选目录内含
///    `bin/javac.exe`；把这些**受控快照**传入本库。
/// 2. **评估器（本文件）**：按固定优先级排序、去重、存在性与主版本匹配，
///    输出 `JdkProbeResult`。
///
/// 该设计让 JDK 探测可被单元测试（受控环境变量与目录快照），且不破坏
/// 本库的确定性与 API 快照测试。风险结论登记于 `EXECUTION-CHAIN.md`。

///|
/// JDK 候选来源（优先级从高到低）。
pub(all) enum JdkSource {
  JavaHome
  Registry
  CommonPath
  PathEntry
}

///|
/// 一个 JDK 候选目录。
///
/// - `path`：绝对路径（Windows 盘符或 POSIX `/` 开头；可带引号，归一化时
///   去除）；
/// - `version`：`release` 文件里的 `JAVA_VERSION`（如 `17.0.9`、
///   `1.8.0_202`）；`None` 表示组合根未提供（按存在性接受，并记诊断）。
pub(all) struct JdkEntry {
  path : String
  version : String?
}

///|
/// 归一化后的候选（`path` 使用 `/` 分隔、保留原始大小写）。
pub(all) struct JdkCandidate {
  path : String
  source : JdkSource
  version : String?
}

///|
/// 探测状态。
pub(all) enum JdkProbeStatus {
  JdkFound
  JdkNotFound
  JdkVersionUnmatched
}

///|
/// 探测结果（纯值）。
///
/// - `candidates`：按来源优先级排序、已去重的候选（含不存在的目录，便于
///   诊断）；
/// - `selected`：第一个「目录存在且版本匹配」的候选；`None` 表示未选中；
/// - `diagnostics`：确定性顺序的诊断信息（不参与判定，供人审阅）。
pub(all) struct JdkProbeResult {
  status : JdkProbeStatus
  selected : JdkCandidate?
  candidates : Array[JdkCandidate]
  diagnostics : Array[String]
}

///|
/// 探测输入：组合根采集的**受控快照**。
///
/// - `java_home`：`JAVA_HOME` 的值（Windows 上可能带双引号）；
/// - `registry_entries`：注册表候选（按期望优先级排列，如 17 → 11 → 8）；
/// - `common_entries`：常见安装根下的候选；
/// - `path_entries`：`PATH` 中解析到的 JDK；
/// - `existing_jdk_dirs`：组合根已确认真实存在且含 `bin/javac.exe`
///   （或 `bin/javac`）的目录；
/// - `required_major`：要求的 JDK 主版本（本机锁定 `17`）。
pub(all) struct JdkProbeEnv {
  java_home : JdkEntry?
  registry_entries : Array[JdkEntry]
  common_entries : Array[JdkEntry]
  path_entries : Array[JdkEntry]
  existing_jdk_dirs : Array[String]
  required_major : Int32
}

///|
/// 内部结构：归一化路径（`display` 保留大小写，`key` 为小写比较键）。
priv struct JdkPath {
  display : String
  key : String
}

///|
/// 内部助手：字符是否 ASCII 字母。
fn jdk_is_ascii_letter(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
}

///|
/// 内部助手：字符是否 ASCII 十进制数字。
fn jdk_is_digit(c : Char) -> Bool {
  c >= '0' && c <= '9'
}

///|
/// 内部助手：数字字符 → 数值。
fn jdk_digit_value(c : Char) -> Int32 {
  c.to_int() - 48
}

///|
/// 内部助手：JDK 目录归一化。
///
/// - 去首尾空白与成对双引号（Windows `JAVA_HOME` 常见写法）；
/// - 拒绝空串、控制字符、相对路径（必须盘符或 `/` 开头）；
/// - `\` → `/`，折叠重复 `/`，去尾部 `/`；
/// - `display` 保留大小写，`key` 小写（Windows 路径大小写不敏感）。
fn normalize_jdk_dir(raw : String) -> JdkPath? {
  let mut text = raw.trim()
  // 去成对双引号（最多两层，容忍 `""C:\..." "` 一类脏值）。
  let mut layer = 0
  while layer < 2 {
    let chars = text.to_array()
    if chars.length() >= 2 &&
      chars[0] == '"' &&
      chars[chars.length() - 1] == '"' {
      let mut inner = ""
      for i in 1..<(chars.length() - 1) {
        inner = inner + "\{chars[i]}"
      }
      text = inner.trim()
      layer = layer + 1
    } else {
      layer = 2
    }
  }
  let chars = text.to_array()
  if chars.length() == 0 {
    return None
  }
  for c in chars {
    if is_control_char(c) {
      return None
    }
  }
  let is_posix = chars[0] == '/'
  let is_drive = chars.length() >= 2 &&
    jdk_is_ascii_letter(chars[0]) &&
    chars[1] == ':'
  if !is_posix && !is_drive {
    return None
  }
  // 盘符后必须是分隔符（拒绝 `C:` / `C:relative` 这类 drive-relative 路径）。
  if is_drive {
    if chars.length() < 3 || (chars[2] != '/' && chars[2] != '\\') {
      return None
    }
  }
  let mut display = ""
  let mut prev_slash = false
  for c in chars {
    if c == '\\' || c == '/' {
      if !prev_slash {
        display = display + "/"
        prev_slash = true
      }
    } else {
      display = display + "\{c}"
      prev_slash = false
    }
  }
  // 去尾部 `/`（保留盘符 / 根语义：`C:` 不再追加）。
  let arr = display.to_array()
  let mut keep = arr.length()
  while keep > 1 && arr[keep - 1] == '/' {
    keep = keep - 1
  }
  if keep != arr.length() {
    let mut cut = ""
    for i in 0..<keep {
      cut = cut + "\{arr[i]}"
    }
    display = cut
  }
  if display == "/" {
    return None
  }
  Some({ display, key: display.to_lower(), })
}

///|
/// 内部助手：解析 JDK 主版本。
///
/// 支持 `17`、`17.0.9`、`21-ea`、`1.8.0_202`（→ 8）；首字符必须是数字，
/// 否则 `None`（fail-closed：版本不可解析时不匹配）。
fn jdk_major(version : String) -> Int32? {
  let chars = version.trim().to_array()
  let n = chars.length()
  if n == 0 || !jdk_is_digit(chars[0]) {
    return None
  }
  let mut i = 0
  let mut first = 0
  while i < n && jdk_is_digit(chars[i]) {
    first = first * 10 + jdk_digit_value(chars[i])
    i = i + 1
  }
  if first == 1 && i < n && chars[i] == '.' {
    let mut j = i + 1
    let mut second = 0
    let mut digits = 0
    while j < n && jdk_is_digit(chars[j]) {
      second = second * 10 + jdk_digit_value(chars[j])
      j = j + 1
      digits = digits + 1
    }
    if digits > 0 {
      return Some(second)
    }
  }
  Some(first)
}

///|
/// 内部助手：压入候选（去重、路径非法记诊断）。
fn push_jdk_candidate(
  candidates : Array[JdkCandidate],
  seen : Array[String],
  diagnostics : Array[String],
  entry : JdkEntry,
  source : JdkSource,
) -> Unit {
  match normalize_jdk_dir(entry.path) {
    Some(path) =>
      if contains_str(seen, path.key) {
        diagnostics.push(
          "重复候选已跳过（" +
          jdk_source_name(source) +
          "）：" +
          path.display,
        )
      } else {
        seen.push(path.key)
        candidates.push({ path: path.display, source, version: entry.version, })
      }
    None =>
      diagnostics.push(
        "候选路径非法已跳过（" +
        jdk_source_name(source) +
        "）：" +
        entry.path,
      )
  }
}

///|
/// 内部助手：候选来源名。
fn jdk_source_name(source : JdkSource) -> String {
  match source {
    JavaHome => "JAVA_HOME"
    Registry => "Registry"
    CommonPath => "CommonPath"
    PathEntry => "PathEntry"
  }
}

///|
/// Windows JDK 探测（纯评估，零 I/O）。
///
/// 优先级：`JAVA_HOME` → 注册表 → 常见路径 → `PATH`；同一目录只保留最先
/// 出现的候选（Windows 大小写不敏感比较）。选择规则：第一个「在
/// `existing_jdk_dirs` 中且主版本等于 `required_major`」的候选；
/// 版本为 `None` 时按存在性接受并记诊断（fail-open，需组合根提供版本才严格）。
///
/// - 返回：`JdkProbeResult`；`status = JdkVersionUnmatched` 表示目录存在但
///   版本不符或版本不可解析；`JdkNotFound` 表示无任何存在的候选。
/// - 错误：`required_major` 不在 8..99 → `InvalidJdkProbe`。
/// - 线程：纯函数，无状态，可并发调用。
pub fn probe_jdk(env : JdkProbeEnv) -> JdkProbeResult raise MoonAndroidError {
  if env.required_major < 8 || env.required_major > 99 {
    raise InvalidJdkProbe(
      "required_major 非法（需 8..99）：" + "\{env.required_major}",
    )
  }
  let candidates : Array[JdkCandidate] = []
  let seen : Array[String] = []
  let diagnostics : Array[String] = []
  // 1) JAVA_HOME
  match env.java_home {
    Some(entry) =>
      if entry.path.trim() == "" {
        diagnostics.push("JAVA_HOME 为空，已忽略")
      } else {
        push_jdk_candidate(
          candidates,
          seen,
          diagnostics,
          entry,
          JdkSource::JavaHome,
        )
      }
    None => diagnostics.push("JAVA_HOME 未设置")
  }
  // 2) 注册表
  for entry in env.registry_entries {
    push_jdk_candidate(
      candidates,
      seen,
      diagnostics,
      entry,
      JdkSource::Registry,
    )
  }
  // 3) 常见路径
  for entry in env.common_entries {
    push_jdk_candidate(
      candidates,
      seen,
      diagnostics,
      entry,
      JdkSource::CommonPath,
    )
  }
  // 4) PATH
  for entry in env.path_entries {
    push_jdk_candidate(
      candidates,
      seen,
      diagnostics,
      entry,
      JdkSource::PathEntry,
    )
  }
  if candidates.length() == 0 {
    diagnostics.push(
      "无任何 JDK 候选：请检查 JAVA_HOME / 注册表 / 安装目录",
    )
  }
  // 存在性集合
  let existing_keys : Array[String] = []
  for dir in env.existing_jdk_dirs {
    match normalize_jdk_dir(dir) {
      Some(path) => existing_keys.push(path.key)
      None => diagnostics.push("existing_jdk_dirs 含非法路径：" + dir)
    }
  }
  let mut selected : JdkCandidate? = None
  let mut has_selected = false
  let mut existed_but_mismatched = false
  for candidate in candidates {
    match normalize_jdk_dir(candidate.path) {
      Some(path) =>
        if contains_str(existing_keys, path.key) {
          match candidate.version {
            Some(version) =>
              match jdk_major(version) {
                Some(major) =>
                  if major == env.required_major {
                    if !has_selected {
                      selected = Some(candidate)
                      has_selected = true
                    }
                  } else {
                    existed_but_mismatched = true
                    diagnostics.push(
                      "版本不匹配（需 " +
                      "\{env.required_major}" +
                      "，得到 " +
                      version +
                      "）：" +
                      candidate.path,
                    )
                  }
                None => {
                  existed_but_mismatched = true
                  diagnostics.push(
                    "版本无法解析：" +
                    version +
                    "（" +
                    candidate.path +
                    "）",
                  )
                }
              }
            None => {
              diagnostics.push(
                "版本未提供，按存在性接受：" + candidate.path,
              )
              if !has_selected {
                selected = Some(candidate)
                has_selected = true
              }
            }
          }
        } else {
          diagnostics.push("目录不存在（跳过）：" + candidate.path)
        }
      None => ()
    }
  }
  let status = if has_selected {
    JdkProbeStatus::JdkFound
  } else if existed_but_mismatched {
    JdkProbeStatus::JdkVersionUnmatched
  } else {
    JdkProbeStatus::JdkNotFound
  }
  { status, selected, candidates, diagnostics, }
}
