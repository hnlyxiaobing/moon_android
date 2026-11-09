// Windows JDK 探测（纯评估器）黑盒测试：优先级、去重、版本匹配与错误路径。

///|
/// 探测状态 → 标签。
fn status_label(status : @moon_android.JdkProbeStatus) -> String {
  match status {
    @moon_android.JdkProbeStatus::JdkFound => "JdkFound"
    @moon_android.JdkProbeStatus::JdkNotFound => "JdkNotFound"
    @moon_android.JdkProbeStatus::JdkVersionUnmatched => "JdkVersionUnmatched"
  }
}

///|
/// 候选来源 → 标签。
fn source_label(source : @moon_android.JdkSource) -> String {
  match source {
    @moon_android.JdkSource::JavaHome => "JavaHome"
    @moon_android.JdkSource::Registry => "Registry"
    @moon_android.JdkSource::CommonPath => "CommonPath"
    @moon_android.JdkSource::PathEntry => "PathEntry"
  }
}

///|
/// 空探测环境（仅 required_major 可配）。
fn empty_jdk_env(required : Int32) -> @moon_android.JdkProbeEnv {
  {
    java_home: None,
    registry_entries: [],
    common_entries: [],
    path_entries: [],
    existing_jdk_dirs: [],
    required_major: required,
  }
}

///|
test "probe_jdk JAVA_HOME 优先：引号/尾斜杠归一化 + 大小写不敏感存在性" {
  let env : @moon_android.JdkProbeEnv = {
    ..empty_jdk_env(17),
    java_home: Some({
      path: "\"C:\\Program Files\\Java\\jdk-17\\\"",
      version: Some("17.0.9"),
    }),
    registry_entries: [
      { path: "C:\\Program Files\\Java\\jdk-17", version: Some("17.0.9"), },
    ],
    existing_jdk_dirs: ["c:/program files/java/jdk-17"],
  }
  let result = @moon_android.probe_jdk(env)
  @test.assert_eq(status_label(result.status), "JdkFound")
  // 去重：JAVA_HOME 与注册表同一目录只保留一个候选（JAVA_HOME 优先）。
  @test.assert_eq(result.candidates.length(), 1)
  @test.assert_eq(source_label(result.candidates[0].source), "JavaHome")
  match result.selected {
    Some(candidate) => {
      @test.assert_eq(candidate.path, "C:/Program Files/Java/jdk-17")
      @test.assert_eq(source_label(candidate.source), "JavaHome")
      match candidate.version {
        Some(version) => @test.assert_eq(version, "17.0.9")
        None => fail("expected version")
      }
    }
    None => fail("expected selected JDK")
  }
}

///|
test "probe_jdk 版本不匹配时回退到注册表候选" {
  let env : @moon_android.JdkProbeEnv = {
    ..empty_jdk_env(17),
    java_home: Some({
      path: "C:\\Program Files\\Java\\jdk-11",
      version: Some("11.0.20"),
    }),
    registry_entries: [
      { path: "C:\\Program Files\\Java\\jdk-17", version: Some("17.0.9"), },
    ],
    existing_jdk_dirs: [
      "C:/Program Files/Java/jdk-11", "C:/Program Files/Java/jdk-17",
    ],
  }
  let result = @moon_android.probe_jdk(env)
  @test.assert_eq(status_label(result.status), "JdkFound")
  @test.assert_eq(result.candidates.length(), 2)
  match result.selected {
    Some(candidate) => {
      @test.assert_eq(source_label(candidate.source), "Registry")
      @test.assert_eq(candidate.path, "C:/Program Files/Java/jdk-17")
    }
    None => fail("expected registry JDK")
  }
}

///|
test "probe_jdk 回退链：常见路径 → PATH" {
  let common_env : @moon_android.JdkProbeEnv = {
    ..empty_jdk_env(17),
    common_entries: [
      {
        path: "C:\\Program Files\\Eclipse Adoptium\\jdk-17.0.9",
        version: Some("17.0.9"),
      },
    ],
    existing_jdk_dirs: ["C:/Program Files/Eclipse Adoptium/jdk-17.0.9"],
  }
  let common_result = @moon_android.probe_jdk(common_env)
  @test.assert_eq(status_label(common_result.status), "JdkFound")
  match common_result.selected {
    Some(candidate) =>
      @test.assert_eq(source_label(candidate.source), "CommonPath")
    None => fail("expected common path JDK")
  }
  let path_env : @moon_android.JdkProbeEnv = {
    ..empty_jdk_env(17),
    path_entries: [{ path: "D:\\Tools\\jdk-17", version: Some("17.0.2"), }],
    existing_jdk_dirs: ["d:/tools/jdk-17"],
  }
  let path_result = @moon_android.probe_jdk(path_env)
  @test.assert_eq(status_label(path_result.status), "JdkFound")
  match path_result.selected {
    Some(candidate) =>
      @test.assert_eq(source_label(candidate.source), "PathEntry")
    None => fail("expected PATH JDK")
  }
}

///|
test "probe_jdk 目录存在但版本不匹配 → JdkVersionUnmatched" {
  let env : @moon_android.JdkProbeEnv = {
    ..empty_jdk_env(17),
    java_home: Some({
      path: "C:\\Program Files\\Java\\jdk-11",
      version: Some("11.0.20"),
    }),
    existing_jdk_dirs: ["C:/Program Files/Java/jdk-11"],
  }
  let result = @moon_android.probe_jdk(env)
  @test.assert_eq(status_label(result.status), "JdkVersionUnmatched")
  assert_true(result.selected is None)
  let mut found = false
  for message in result.diagnostics {
    if message.contains("版本不匹配") {
      found = true
    }
  }
  assert_true(found)
}

///|
test "probe_jdk 全部候选目录不存在 → JdkNotFound" {
  let env : @moon_android.JdkProbeEnv = {
    ..empty_jdk_env(17),
    java_home: Some({
      path: "C:\\Program Files\\Java\\jdk-17",
      version: Some("17.0.9"),
    }),
    existing_jdk_dirs: [],
  }
  let result = @moon_android.probe_jdk(env)
  @test.assert_eq(status_label(result.status), "JdkNotFound")
  assert_true(result.selected is None)
  @test.assert_eq(result.candidates.length(), 1)
}

///|
test "probe_jdk 空环境 → JdkNotFound 且给出 JAVA_HOME 诊断" {
  let result = @moon_android.probe_jdk(empty_jdk_env(17))
  @test.assert_eq(status_label(result.status), "JdkNotFound")
  assert_true(result.selected is None)
  @test.assert_eq(result.candidates.length(), 0)
  let mut has_hint = false
  let mut has_no_candidate = false
  for message in result.diagnostics {
    if message.contains("JAVA_HOME 未设置") {
      has_hint = true
    }
    if message.contains("无任何 JDK 候选") {
      has_no_candidate = true
    }
  }
  assert_true(has_hint)
  assert_true(has_no_candidate)
}

///|
test "probe_jdk required_major 非法 → InvalidJdkProbe" {
  for bad in [0, 7, 100, -1] {
    match
      @test.expect_error(() => @moon_android.probe_jdk(empty_jdk_env(bad))) {
      InvalidJdkProbe(msg) => assert_true(msg.contains("required_major"), msg~)
      _ => fail("expected InvalidJdkProbe for " + "\{bad}")
    }
  }
}

///|
test "probe_jdk 非法候选路径跳过且不 panic" {
  let env : @moon_android.JdkProbeEnv = {
    ..empty_jdk_env(17),
    java_home: Some({ path: "relative/jdk-17", version: Some("17"), }),
    registry_entries: [{ path: "", version: None, }],
    common_entries: [{ path: "C:\\bad\n\\path", version: Some("17.0.9"), }],
    existing_jdk_dirs: ["relative/also-bad"],
  }
  let result = @moon_android.probe_jdk(env)
  @test.assert_eq(status_label(result.status), "JdkNotFound")
  @test.assert_eq(result.candidates.length(), 0)
  let mut has_skipped = false
  for message in result.diagnostics {
    if message.contains("候选路径非法") {
      has_skipped = true
    }
  }
  assert_true(has_skipped)
}

///|
test "probe_jdk 版本不可解析 → 不匹配（fail-closed）" {
  let env : @moon_android.JdkProbeEnv = {
    ..empty_jdk_env(17),
    java_home: Some({
      path: "C:\\Java\\jdk-unknown",
      version: Some("jdk-unknown"),
    }),
    existing_jdk_dirs: ["C:/Java/jdk-unknown"],
  }
  let result = @moon_android.probe_jdk(env)
  @test.assert_eq(status_label(result.status), "JdkVersionUnmatched")
  assert_true(result.selected is None)
}

///|
test "probe_jdk 版本未提供按存在性接受并记诊断" {
  let env : @moon_android.JdkProbeEnv = {
    ..empty_jdk_env(17),
    java_home: Some({ path: "C:\\Java\\jdk-17", version: None, }),
    existing_jdk_dirs: ["C:/Java/jdk-17"],
  }
  let result = @moon_android.probe_jdk(env)
  @test.assert_eq(status_label(result.status), "JdkFound")
  let mut has_note = false
  for message in result.diagnostics {
    if message.contains("版本未提供") {
      has_note = true
    }
  }
  assert_true(has_note)
}

///|
test "probe_jdk 兼容旧版 1.8.0_202 → 主版本 8" {
  let env : @moon_android.JdkProbeEnv = {
    ..empty_jdk_env(8),
    java_home: Some({
      path: "C:\\Program Files\\Java\\jdk1.8.0_202",
      version: Some("1.8.0_202"),
    }),
    existing_jdk_dirs: ["C:/Program Files/Java/jdk1.8.0_202"],
  }
  let result = @moon_android.probe_jdk(env)
  @test.assert_eq(status_label(result.status), "JdkFound")
}
