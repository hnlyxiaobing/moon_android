// L1 性质层（W9）：变形律 P1/P4/P5/P6/P8/P9/P10 缺口补齐。
// P2/P3 既有用例在码；P7 防火墙律由每包 DoD 门禁与 tools/ref-scan.sh 承载。

///|
/// 内部助手：子串出现次数。
fn count_occurrences(text : String, needle : String) -> Int32 {
  let mut count = 0
  let mut rest = text
  while true {
    match rest.find(needle) {
      Some(pos) => {
        count = count + 1
        rest = rest[pos + needle.length():].to_owned()
      }
      None => break
    }
  }
  count
}

///|
/// 内部助手：XML 内容中 `&` 必须引导合法实体（P10 全文扫描）。
fn xml_entities_ok(content : String) -> Bool {
  let chars = content.to_array()
  let mut i = 0
  while i < chars.length() {
    if chars[i] == '&' {
      let tail = content[i:].to_owned()
      let ok = tail.has_prefix("&amp;") ||
        tail.has_prefix("&lt;") ||
        tail.has_prefix("&gt;") ||
        tail.has_prefix("&quot;") ||
        tail.has_prefix("&apos;") ||
        tail.has_prefix("&#")
      if !ok {
        return false
      }
    }
    i = i + 1
  }
  true
}

///|
test "P1 确定性律：plan_build / render_native_manifest / probe_jdk 双次逐字一致" {
  let config = demo_config()
  let p1 = @moon_android.plan_build(config, [])
  let p2 = @moon_android.plan_build(config, [])
  @test.assert_eq(
    @moon_android.render_script(p1),
    @moon_android.render_script(p2),
  )
  let libs = @moon_android.attach_native_hashes(
    @moon_android.plan_native_libs(@moon_android.dual_abi_set(), "libapp.so"),
    [
      { abi: @moon_android.Abi::Arm64V8a, sha256: good_sha256(), },
      { abi: @moon_android.Abi::ArmeabiV7a, sha256: second_sha256(), },
    ],
  )
  @test.assert_eq(
    @moon_android.render_native_manifest(libs),
    @moon_android.render_native_manifest(libs),
  )
  let env : @moon_android.JdkProbeEnv = {
    ..empty_jdk_env(17),
    java_home: Some({ path: "C:\\Java\\jdk-17", version: Some("17.0.9"), }),
    existing_jdk_dirs: ["C:/Java/jdk-17"],
  }
  @test.assert_eq(
    probe_result_key(@moon_android.probe_jdk(env)),
    probe_result_key(@moon_android.probe_jdk(env)),
  )
}

///|
test "P4 多重集合序不变律：verify_artifact 对 ABI/签名任意排列结论不变" {
  let plan = @moon_android.plan_build(
    demo_config(),
    @moon_android.dual_abi_set(),
  )
  let base : @moon_android.Artifact = {
    path: "com.example.app.apk",
    size_bytes: 1024UL,
    sha256: good_sha256(),
    abis: [@moon_android.Abi::Arm64V8a, @moon_android.Abi::ArmeabiV7a],
    signatures: [
      @moon_android.SigningScheme::V2,
      @moon_android.SigningScheme::V3,
    ],
  }
  assert_true(@moon_android.verify_artifact(plan, base))
  let permuted : @moon_android.Artifact = {
    ..base,
    abis: [@moon_android.Abi::ArmeabiV7a, @moon_android.Abi::Arm64V8a],
    signatures: [
      @moon_android.SigningScheme::V3,
      @moon_android.SigningScheme::V2,
    ],
  }
  assert_true(@moon_android.verify_artifact(plan, permuted))
  // 负例同样序不变：缺一个 ABI 无论排列均 false。
  let missing : @moon_android.Artifact = {
    ..base,
    abis: [@moon_android.Abi::ArmeabiV7a],
  }
  assert_true(!@moon_android.verify_artifact(plan, missing))
}

///|
test "P5 ABI 往返律：parse_abi_dir_name(abi_dir_name(a)) == a（4 ABI 穷举）" {
  let all = [
    @moon_android.Abi::Arm64V8a,
    @moon_android.Abi::ArmeabiV7a,
    @moon_android.Abi::X86,
    @moon_android.Abi::X86_64,
  ]
  for abi in all {
    let roundtrip = @moon_android.parse_abi_dir_name(
      @moon_android.abi_dir_name(abi),
    )
    @test.assert_eq(
      @moon_android.abi_dir_name(roundtrip),
      @moon_android.abi_dir_name(abi),
    )
  }
}

///|
test "P6 清单往返律：数据行数 == libs 长度且逐行双射" {
  let libs = @moon_android.attach_native_hashes(
    @moon_android.plan_native_libs(@moon_android.dual_abi_set(), "libapp.so"),
    [
      { abi: @moon_android.Abi::Arm64V8a, sha256: good_sha256(), },
      { abi: @moon_android.Abi::ArmeabiV7a, sha256: second_sha256(), },
    ],
  )
  let text = @moon_android.render_native_manifest(libs)
  // 数据行以 "lib/" 开头，紧跟换行（首行是注释头）。
  @test.assert_eq(count_occurrences(text, "\nlib/"), libs.length())
  for lib in libs {
    let hash = match lib.sha256 {
      Some(h) => h
      None => fail("expected registered hash")
    }
    let expected = "lib/" + lib.dir + "/" + lib.soname + "  sha256=" + hash
    assert_true(text.contains(expected), msg=expected)
    @test.assert_eq(count_occurrences(text, expected), 1)
  }
}

///|
test "P8 模板一致律：plan_template(p).build_plan == plan_build(p.config, [])" {
  let params = demo_template()
  let tree = @moon_android.plan_template(params)
  let direct = @moon_android.plan_build(params.config, [])
  @test.assert_eq(tree.build_plan.steps.length(), direct.steps.length())
  @test.assert_eq(tree.build_plan.inputs, direct.inputs)
  @test.assert_eq(tree.build_plan.outputs, direct.outputs)
  @test.assert_eq(
    @moon_android.render_script(tree.build_plan),
    @moon_android.render_script(direct),
  )
  @test.assert_eq(
    tree.build_plan.config.package_id.name,
    direct.config.package_id.name,
  )
  @test.assert_eq(tree.build_plan.config.min_sdk, direct.config.min_sdk)
  @test.assert_eq(tree.build_plan.config.target_sdk, direct.config.target_sdk)
}

///|
test "P9 heredoc 安全律：合法树每个分隔符恰出现 2 次（开/闭）" {
  let tree = @moon_android.plan_template(demo_template())
  let text = @moon_android.render_template_script(tree)
  for i in 0..<tree.files.length() {
    let marker = "MOON_ANDROID_EOF_" + "\{i}"
    @test.assert_eq(count_occurrences(text, marker), 2)
  }
}

///|
test "P10 XML 转义律：五字符注入必被转义且全文无裸 &" {
  let params : @moon_android.TemplateParams = {
    ..demo_template(),
    app_name: "A&B<C>D\"E'F",
  }
  let tree = @moon_android.plan_template(params)
  let manifest = file_content(tree, "AndroidManifest.xml")
  let strings = file_content(tree, "res/values/strings.xml")
  // app_name 经 @string/app_name 间接引用，转义落在 strings.xml。
  assert_true(manifest.contains("@string/app_name"))
  assert_true(strings.contains("A&amp;B&lt;C&gt;D&quot;E&apos;F"))
  assert_true(!strings.contains("A&B<C>"))
  assert_true(xml_entities_ok(manifest))
  assert_true(xml_entities_ok(strings))
  // entry_url 的 & 亦须转义（template_config 带 ?a=1&b=2）。
  assert_true(manifest.contains("a=1&amp;b=2"))
  assert_true(!manifest.contains("a=1&b=2"))
}
