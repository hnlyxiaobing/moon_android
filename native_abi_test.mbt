// 双 ABI `.so` 管理的黑盒测试：目录/顺序、清单校验、哈希登记与错误路径。

///|
/// 第二个合法 sha256 样例（与 good_sha256 不同）。
fn second_sha256() -> String {
  "fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210"
}

///|
test "plan_native_libs 双 ABI 目录、顺序与未登记哈希" {
  let abis = @moon_android.dual_abi_set()
  @test.assert_eq(abis.length(), 2)
  @test.assert_eq(abi_label(abis[0]), "arm64-v8a")
  @test.assert_eq(abi_label(abis[1]), "armeabi-v7a")
  let libs = @moon_android.plan_native_libs(abis, "libapp.so")
  @test.assert_eq(libs.length(), 2)
  @test.assert_eq(libs[0].dir, "arm64-v8a")
  @test.assert_eq(libs[0].soname, "libapp.so")
  assert_true(libs[0].sha256 is None)
  @test.assert_eq(libs[1].dir, "armeabi-v7a")
  assert_true(libs[1].sha256 is None)
  // 顺序按输入保留，不重排。
  let reversed = @moon_android.plan_native_libs(
    [@moon_android.Abi::ArmeabiV7a, @moon_android.Abi::Arm64V8a],
    "libapp.so",
  )
  @test.assert_eq(reversed[0].dir, "armeabi-v7a")
  @test.assert_eq(reversed[1].dir, "arm64-v8a")
}

///|
test "plan_native_libs 空 ABI / 重复 ABI → UnsupportedAbi" {
  match
    @test.expect_error(() => @moon_android.plan_native_libs([], "libapp.so")) {
    UnsupportedAbi(name) => @test.assert_eq(name, "none")
    _ => fail("expected UnsupportedAbi(none)")
  }
  match
    @test.expect_error(() => {
      @moon_android.plan_native_libs(
        [@moon_android.Abi::Arm64V8a, @moon_android.Abi::Arm64V8a],
        "libapp.so",
      )
    }) {
    UnsupportedAbi(name) => @test.assert_eq(name, "arm64-v8a")
    _ => fail("expected UnsupportedAbi(duplicate arm64-v8a)")
  }
}

///|
test "plan_native_libs 非法 soname → InvalidNativeLib" {
  let bad_names = [
    "", "app.so", "lib.so", "libapp.dll", "liba/b.so", "liba\\b.so", "lib..so", "lib app.so",
    "libapp.so ", "libapp.so/../evil.so",
  ]
  for bad in bad_names {
    match
      @test.expect_error(() => {
        @moon_android.plan_native_libs([@moon_android.Abi::Arm64V8a], bad)
      }) {
      InvalidNativeLib(msg) => assert_true(msg.contains("soname"), msg~)
      _ => fail("expected InvalidNativeLib for " + bad)
    }
  }
  // 合法变体：下划线 / 点 / 连字符 / 大写。
  for
    good in [
      "libapp.so", "libapp_core.so", "libapp.v2.so", "libapp-1.so", "libApp.so",
    ] {
    let libs = @moon_android.plan_native_libs(
      [@moon_android.Abi::Arm64V8a],
      good,
    )
    @test.assert_eq(libs[0].soname, good)
  }
}

///|
test "parse_abi_dir_name 反解合法 ABI 名" {
  let cases : Array[(String, String)] = [
    ("arm64-v8a", "arm64-v8a"),
    ("armeabi-v7a", "armeabi-v7a"),
    ("x86", "x86"),
    ("x86_64", "x86_64"),
  ]
  for item in cases {
    let abi = @moon_android.parse_abi_dir_name(item.0)
    @test.assert_eq(abi_label(abi), item.1)
  }
}

///|
test "parse_abi_dir_name 非法 ABI 名 → UnsupportedAbi" {
  for
    bad in [
      "", "armeabi", "ARM64-V8A", "arm64-v8a ", " arm64-v8a", "arm64", "mips",
    ] {
    match @test.expect_error(() => @moon_android.parse_abi_dir_name(bad)) {
      UnsupportedAbi(name) => @test.assert_eq(name, bad)
      _ => fail("expected UnsupportedAbi for " + bad)
    }
  }
}

///|
test "attach_native_hashes 双 ABI 回填成功且不改输入" {
  let libs = @moon_android.plan_native_libs(
    @moon_android.dual_abi_set(),
    "libapp.so",
  )
  let attached = @moon_android.attach_native_hashes(libs, [
    { abi: @moon_android.Abi::Arm64V8a, sha256: good_sha256(), },
    { abi: @moon_android.Abi::ArmeabiV7a, sha256: second_sha256(), },
  ])
  @test.assert_eq(attached.length(), 2)
  match attached[0].sha256 {
    Some(hash) => @test.assert_eq(hash, good_sha256())
    None => fail("expected registered sha256 for arm64-v8a")
  }
  match attached[1].sha256 {
    Some(hash) => @test.assert_eq(hash, second_sha256())
    None => fail("expected registered sha256 for armeabi-v7a")
  }
  // 输入仍是未登记状态（纯函数）。
  assert_true(libs[0].sha256 is None)
  assert_true(libs[1].sha256 is None)
}

///|
test "attach_native_hashes 缺失 ABI 哈希 → MissingAbi" {
  let libs = @moon_android.plan_native_libs(
    @moon_android.dual_abi_set(),
    "libapp.so",
  )
  match
    @test.expect_error(() => {
      @moon_android.attach_native_hashes(libs, [
        { abi: @moon_android.Abi::Arm64V8a, sha256: good_sha256(), },
      ])
    }) {
    MissingAbi(name) => @test.assert_eq(name, "armeabi-v7a")
    _ => fail("expected MissingAbi(armeabi-v7a)")
  }
}

///|
test "attach_native_hashes 重复/未知 ABI/非法哈希 → InvalidNativeLib" {
  let libs = @moon_android.plan_native_libs(
    @moon_android.dual_abi_set(),
    "libapp.so",
  )
  match
    @test.expect_error(() => {
      @moon_android.attach_native_hashes(libs, [
        { abi: @moon_android.Abi::Arm64V8a, sha256: good_sha256(), },
        { abi: @moon_android.Abi::Arm64V8a, sha256: second_sha256(), },
      ])
    }) {
    InvalidNativeLib(msg) => assert_true(msg.contains("重复"), msg~)
    _ => fail("expected InvalidNativeLib(duplicate hash)")
  }
  match
    @test.expect_error(() => {
      @moon_android.attach_native_hashes(libs, [
        { abi: @moon_android.Abi::X86, sha256: good_sha256(), },
      ])
    }) {
    InvalidNativeLib(msg) => assert_true(msg.contains("不在清单"), msg~)
    _ => fail("expected InvalidNativeLib(unknown abi)")
  }
  match
    @test.expect_error(() => {
      @moon_android.attach_native_hashes(libs, [
        { abi: @moon_android.Abi::Arm64V8a, sha256: "zz", },
        { abi: @moon_android.Abi::ArmeabiV7a, sha256: second_sha256(), },
      ])
    }) {
    InvalidNativeLib(msg) => assert_true(msg.contains("sha256"), msg~)
    _ => fail("expected InvalidNativeLib(bad hash)")
  }
}

///|
test "validate_native_manifest 通过/未登记哈希/缺失 ABI/重复/目录漂移" {
  let libs = @moon_android.plan_native_libs(
    @moon_android.dual_abi_set(),
    "libapp.so",
  )
  // 未登记哈希：fail-closed。
  match
    @test.expect_error(() => {
      @moon_android.validate_native_manifest(libs, @moon_android.dual_abi_set())
    }) {
    InvalidNativeLib(msg) => assert_true(msg.contains("未登记"), msg~)
    _ => fail("expected InvalidNativeLib(unregistered)")
  }
  let attached = @moon_android.attach_native_hashes(libs, [
    { abi: @moon_android.Abi::Arm64V8a, sha256: good_sha256(), },
    { abi: @moon_android.Abi::ArmeabiV7a, sha256: second_sha256(), },
  ])
  @moon_android.validate_native_manifest(attached, @moon_android.dual_abi_set())
  // 单 ABI 清单对双 ABI required：缺 armeabi-v7a。
  let single = @moon_android.attach_native_hashes(
    @moon_android.plan_native_libs([@moon_android.Abi::Arm64V8a], "libapp.so"),
    [{ abi: @moon_android.Abi::Arm64V8a, sha256: good_sha256(), }],
  )
  match
    @test.expect_error(() => {
      @moon_android.validate_native_manifest(
        single,
        @moon_android.dual_abi_set(),
      )
    }) {
    MissingAbi(name) => @test.assert_eq(name, "armeabi-v7a")
    _ => fail("expected MissingAbi(armeabi-v7a)")
  }
  // 重复 ABI 目录。
  let duplicate : Array[@moon_android.NativeLib] = [
    {
      abi: @moon_android.Abi::Arm64V8a,
      dir: "arm64-v8a",
      soname: "libapp.so",
      sha256: Some(good_sha256()),
    },
    {
      abi: @moon_android.Abi::Arm64V8a,
      dir: "arm64-v8a",
      soname: "libapp.so",
      sha256: Some(second_sha256()),
    },
  ]
  match
    @test.expect_error(() => {
      @moon_android.validate_native_manifest(duplicate, [])
    }) {
    UnsupportedAbi(name) => @test.assert_eq(name, "arm64-v8a")
    _ => fail("expected UnsupportedAbi(duplicate)")
  }
  // 目录与 ABI 不一致。
  let drifted : Array[@moon_android.NativeLib] = [
    {
      abi: @moon_android.Abi::Arm64V8a,
      dir: "x86",
      soname: "libapp.so",
      sha256: Some(good_sha256()),
    },
  ]
  match
    @test.expect_error(() => @moon_android.validate_native_manifest(drifted, [])) {
    InvalidNativeLib(msg) => assert_true(msg.contains("目录"), msg~)
    _ => fail("expected InvalidNativeLib(dir drift)")
  }
  // 空清单。
  match
    @test.expect_error(() => {
      @moon_android.validate_native_manifest([], @moon_android.dual_abi_set())
    }) {
    UnsupportedAbi(name) => @test.assert_eq(name, "none")
    _ => fail("expected UnsupportedAbi(none)")
  }
}

///|
test "render_native_manifest 确定性文本与未登记拒绝" {
  let libs = @moon_android.plan_native_libs(
    @moon_android.dual_abi_set(),
    "libapp.so",
  )
  match @test.expect_error(() => @moon_android.render_native_manifest(libs)) {
    InvalidNativeLib(msg) => assert_true(msg.contains("未登记"), msg~)
    _ => fail("expected InvalidNativeLib(unregistered)")
  }
  let attached = @moon_android.attach_native_hashes(libs, [
    { abi: @moon_android.Abi::Arm64V8a, sha256: good_sha256(), },
    { abi: @moon_android.Abi::ArmeabiV7a, sha256: second_sha256(), },
  ])
  let text = @moon_android.render_native_manifest(attached)
  assert_true(text.contains("# entries: 2"))
  assert_true(text.contains("lib/arm64-v8a/libapp.so  sha256=" + good_sha256()))
  assert_true(
    text.contains("lib/armeabi-v7a/libapp.so  sha256=" + second_sha256()),
  )
  @test.assert_eq(text, @moon_android.render_native_manifest(attached))
}
