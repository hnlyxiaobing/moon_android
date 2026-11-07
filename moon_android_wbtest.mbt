// Whitebox tests run within the package scope.
// Use them to validate internal helpers or invariants.
// Keep them focused; public behavior belongs in `_test.mbt`.

///|
/// 全部必锁版本齐备的工具链样例（与黑盒测试同规格）。
fn locked_toolchain() -> ToolchainVersions {
  {
    moon_cli: "moon 0.1.20261102",
    moonc: "v0.10.19+bee578715",
    core: "0.1.0",
    ndk: "r27",
    build_tools: "34.0.0",
    platform: "android-34",
    jdk: "17",
    cmake: Some("3.22.1"),
  }
}

///|
/// 合法构建配置样例（与黑盒测试同规格）。
fn demo_config() -> BuildConfig {
  {
    package_id: { name: "com.example.app", },
    activity: WebView,
    entry_url: Some("https://example.com/index.html"),
    abis: [Arm64V8a],
    min_sdk: 24,
    target_sdk: 34,
    signing_schemes: [V2, V3],
    keystore_ref: "@keys/release.jks",
    profile: BuildProfile::Debug,
    toolchain: locked_toolchain(),
    extra_native_libs: [],
  }
}

///|
/// 合法 sha256 值样例（64 位十六进制）。
fn good_sha256() -> String {
  "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
}

///|
/// 构造 `MissingGate` 的唯一途径是 raise（错误值不可直接构造）。
fn raise_missing_gate() -> Unit raise MoonAndroidError {
  raise MissingGate(Gate::VersionLock)
}

///|
test "step_rank 规范全序严格递增且 Zipalign 早于 Apksigner" {
  let steps = canonical_steps()
  @test.assert_eq(steps.length(), 10)
  for i in 1..<steps.length() {
    assert_true(step_rank(steps[i - 1]) < step_rank(steps[i]))
  }
  assert_true(step_rank(Zipalign) < step_rank(Apksigner))
  assert_true(step_rank(CrossCompile) == 0)
  assert_true(step_rank(AdbInstall) == 9)
  @test.assert_eq(step_name(Zipalign), "Zipalign")
  @test.assert_eq(step_name(Apksigner), "Apksigner")
}

///|
test "valid_package_name 规则矩阵" {
  for
    good in [
      "com.example.app", "a.b", "com.example.app2", "a.b_c", "Com.Example.App9",
    ] {
    assert_true(valid_package_name(good), msg=good)
  }
  for
    bad in [
      "", "app", "com.", ".com.app", "com..app", "com.1app.app", "com.app!.x", "com.app x",
      "com.-app.app", "1com.app", "com.app.",
    ] {
    assert_true(!valid_package_name(bad), msg=bad)
  }
}

///|
test "looks_like_key_material 检测矩阵" {
  for
    bad in [
      "-----BEGIN PRIVATE KEY-----\nMII...", "-----BEGIN CERTIFICATE-----", "x?storepass=secret",
      "KEYPASS=hunter2", "some password field", "data:application/octet-stream;base64,MIICdwIBADANBg",
    ] {
    assert_true(looks_like_key_material(bad), msg=bad)
  }
  for
    good in [
      "@keys/release.jks", "file:relative/path.jks", "secret-store://alias/release",
      "keystore-ref-1",
    ] {
    assert_true(!looks_like_key_material(good), msg=good)
  }
}

///|
test "is_sha256_hex 值规格" {
  assert_true(is_sha256_hex(good_sha256()))
  assert_true(
    is_sha256_hex(
      "0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF",
    ),
  )
  for
    bad in [
      "", "zz", "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcde",
      "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0",
    ] {
    assert_true(!is_sha256_hex(bad), msg=bad)
  }
}

///|
test "first_unlocked_field 按声明序报告缺失字段" {
  let base = locked_toolchain()
  assert_true(first_unlocked_field(base) is None)
  assert_true(
    first_unlocked_field({ ..base, moon_cli: "", }) is Some("moon_cli"),
  )
  assert_true(first_unlocked_field({ ..base, moonc: "", }) is Some("moonc"))
  assert_true(first_unlocked_field({ ..base, core: "", }) is Some("core"))
  assert_true(first_unlocked_field({ ..base, ndk: "", }) is Some("ndk"))
  assert_true(
    first_unlocked_field({ ..base, build_tools: "", }) is Some("build_tools"),
  )
  assert_true(
    first_unlocked_field({ ..base, platform: "", }) is Some("platform"),
  )
  assert_true(first_unlocked_field({ ..base, jdk: "", }) is Some("jdk"))
  // cmake 为可选项，不在版本锁报告范围内。
  assert_true(first_unlocked_field({ ..base, cmake: None, }) is None)
}

///|
test "tool_version 工具 → 版本锁映射" {
  let base = locked_toolchain()
  assert_true(tool_version("cmake", base) is Some("3.22.1"))
  assert_true(tool_version("cmake", { ..base, cmake: None, }) is None)
  assert_true(tool_version("cmake", { ..base, cmake: Some(""), }) is None)
  assert_true(tool_version("ndk", base) is Some("r27"))
  assert_true(tool_version("aapt2", base) is Some("34.0.0"))
  assert_true(tool_version("d8", base) is Some("34.0.0"))
  assert_true(tool_version("zipalign", base) is Some("34.0.0"))
  assert_true(tool_version("apksigner", base) is Some("34.0.0"))
  assert_true(tool_version("javac", base) is Some("17"))
  assert_true(tool_version("jar", base) is Some("17"))
  assert_true(tool_version("android.jar", base) is Some("android-34"))
  // adb 为设备侧工具，不参与版本锁。
  assert_true(tool_version("adb", base) is Some("device-side"))
  assert_true(tool_version("aapt2", { ..base, build_tools: "", }) is None)
  assert_true(tool_version("javac", { ..base, jdk: "", }) is None)
}

///|
test "tools_of_step 每步工具齐全且可解析" {
  let base = locked_toolchain()
  for step in canonical_steps() {
    assert_true(tools_of_step(step).length() > 0, msg=step_name(step))
    for tool in tools_of_step(step) {
      assert_true(tool_version(tool, base) is Some(_), msg=step_name(step))
    }
  }
  @test.assert_eq(join_comma(tools_of_step(CrossCompile)), "cmake, ndk")
  @test.assert_eq(join_comma(tools_of_step(AdbInstall)), "adb")
}

///|
test "validate_step_order 与 validate_tools 负例（包内可达路径）" {
  // 重复步骤 → InvalidStepOrder(name, name)。
  match @test.expect_error(() => validate_step_order([Zipalign, Zipalign])) {
    InvalidStepOrder(a, b) => {
      @test.assert_eq(a, "Zipalign")
      @test.assert_eq(b, "Zipalign")
    }
    _ => fail("expected InvalidStepOrder(duplicate)")
  }
  // AdbInstall 早于 Verify → InvalidStepOrder("AdbInstall", "Verify")。
  match @test.expect_error(() => validate_step_order([AdbInstall, Verify])) {
    InvalidStepOrder(c, d) => {
      @test.assert_eq(c, "AdbInstall")
      @test.assert_eq(d, "Verify")
    }
    _ => fail("expected InvalidStepOrder(inversion)")
  }
  // 手造计划越过 plan_build 锁检查时，缺失工具由渲染/校验路径报告。
  match
    @test.expect_error(() => {
      validate_tools([Verify], { ..locked_toolchain(), build_tools: "", })
    }) {
    MissingTool(name) => @test.assert_eq(name, "apksigner")
    _ => fail("expected MissingTool(apksigner)")
  }
  // 合法序列不报错。
  validate_step_order(canonical_steps())
  validate_tools(canonical_steps(), locked_toolchain())
}

///|
test "same_abi_multiset / same_scheme_multiset 多重集合比对" {
  assert_true(same_abi_multiset([], []))
  assert_true(same_abi_multiset([X86, Arm64V8a], [Arm64V8a, X86]))
  assert_true(!same_abi_multiset([X86], []))
  assert_true(!same_abi_multiset([X86, X86], [X86, Arm64V8a]))
  assert_true(!same_abi_multiset([X86], [Arm64V8a]))
  assert_true(same_scheme_multiset([V2, V3], [V3, V2]))
  assert_true(!same_scheme_multiset([V2, V2], [V2, V3]))
  assert_true(!same_scheme_multiset([V2], [V2, V3]))
}

///|
test "soname 取包名末段" {
  let config = demo_config()
  @test.assert_eq(soname(config), "libapp.so")
  @test.assert_eq(
    soname({ ..config, package_id: { name: "a.b_cd", }, }),
    "libb_cd.so",
  )
}

///|
test "join_comma 与 step_input / step_output 命名稳定" {
  @test.assert_eq(join_comma([]), "")
  @test.assert_eq(join_comma(["a"]), "a")
  @test.assert_eq(join_comma(["a", "b", "c"]), "a, b, c")
  let config = demo_config()
  @test.assert_eq(step_input(Zipalign, config), "com.example.app-unsigned.apk")
  @test.assert_eq(step_output(Zipalign, config), "com.example.app-aligned.apk")
  @test.assert_eq(step_output(Apksigner, config), "com.example.app.apk")
  @test.assert_eq(step_output(AdbInstall, config), "device/com.example.app.apk")
}

///|
test "validate_signing / validate_abis 包内直测" {
  validate_signing(demo_config())
  validate_abis([Arm64V8a, X86])
  match
    @test.expect_error(() => {
      validate_signing({ ..demo_config(), signing_schemes: [], })
    }) {
    SigningSchemeConflict(msg) => assert_true(msg.contains("为空"), msg~)
    _ => fail("expected SigningSchemeConflict")
  }
  match @test.expect_error(() => validate_abis([])) {
    UnsupportedAbi(name) => @test.assert_eq(name, "none")
    _ => fail("expected UnsupportedAbi(none)")
  }
}

///|
test "MoonAndroidError::MissingGate 构造可用（错误模型完整性）" {
  match @test.expect_error(() => raise_missing_gate()) {
    MissingGate(gate) => assert_true(gate is Gate::VersionLock)
    _ => fail("expected MissingGate")
  }
}

///|
struct TestPlanner {
  config : BuildConfig
}

///|
impl BuildPlanner for TestPlanner with fn plan(self) -> BuildPlan raise MoonAndroidError {
  plan_build(self.config, [])
}

///|
test "BuildPlanner 契约可由实现者兑现（plan = plan_build）" {
  let planner = TestPlanner::{ config: demo_config(), }
  let plan = BuildPlanner::plan(planner)
  @test.assert_eq(plan.steps.length(), 10)
  @test.assert_eq(plan.config.package_id.name, "com.example.app")
}
