// Blackbox tests run against the package's public API. Use `@moon_android` to import.
// Prefer high-level behaviors over implementation details.
// Run `moon test` to execute and `moon test --update` to refresh snapshots.

///|
/// 全部必锁版本齐备的工具链样例（版本锁策略与 pin 值见 docs/DECISIONS.md）。
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
/// 合法构建配置样例（WebView 壳、单 ABI、V2+V3 签名）。
fn demo_config() -> @moon_android.BuildConfig {
  {
    package_id: { name: "com.example.app", },
    activity: @moon_android.ActivityKind::WebView,
    entry_url: Some("https://example.com/index.html"),
    abis: [@moon_android.Abi::Arm64V8a],
    min_sdk: 24,
    target_sdk: 34,
    signing_schemes: [
      @moon_android.SigningScheme::V2,
      @moon_android.SigningScheme::V3,
    ],
    keystore_ref: "@keys/release.jks",
    profile: @moon_android.BuildProfile::Debug,
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
/// ABI → 目录名标签（与 API 文档一致）。
fn abi_label(abi : @moon_android.Abi) -> String {
  match abi {
    @moon_android.Abi::ArmeabiV7a => "armeabi-v7a"
    @moon_android.Abi::Arm64V8a => "arm64-v8a"
    @moon_android.Abi::X86 => "x86"
    @moon_android.Abi::X86_64 => "x86_64"
  }
}

///|
/// 步骤 → 名称标签。
fn step_label(step : @moon_android.BuildStep) -> String {
  match step {
    @moon_android.BuildStep::CrossCompile => "CrossCompile"
    @moon_android.BuildStep::Aapt2Compile => "Aapt2Compile"
    @moon_android.BuildStep::Aapt2Link => "Aapt2Link"
    @moon_android.BuildStep::Javac => "Javac"
    @moon_android.BuildStep::D8 => "D8"
    @moon_android.BuildStep::Assemble => "Assemble"
    @moon_android.BuildStep::Zipalign => "Zipalign"
    @moon_android.BuildStep::Apksigner => "Apksigner"
    @moon_android.BuildStep::Verify => "Verify"
    @moon_android.BuildStep::AdbInstall => "AdbInstall"
  }
}

///|
/// 门禁 → 名称标签。
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
/// 标签数组拼接。
fn join_labels(labels : Array[String]) -> String {
  let mut out = ""
  for i in 0..<labels.length() {
    if i > 0 {
      out = out + ", "
    }
    out = out + labels[i]
  }
  out
}

///|
/// 手造计划（用于渲染/校验的负例）：步骤给定，输入输出为空。
fn raw_plan(
  steps : Array[@moon_android.BuildStep],
  config : @moon_android.BuildConfig,
) -> @moon_android.BuildPlan {
  { steps, inputs: [], outputs: [], config, }
}

///|
test "plan_build 产出规范 10 步且 Zipalign 早于 Apksigner" {
  let plan = @moon_android.plan_build(demo_config(), [])
  @test.assert_eq(plan.steps.length(), 10)
  @test.assert_eq(plan.inputs.length(), 10)
  @test.assert_eq(plan.outputs.length(), 10)
  let labels : Array[String] = []
  for step in plan.steps {
    labels.push(step_label(step))
  }
  @test.assert_eq(
    join_labels(labels),
    "CrossCompile, Aapt2Compile, Aapt2Link, Javac, D8, Assemble, Zipalign, Apksigner, Verify, AdbInstall",
  )
  // 硬约束：Zipalign 必须早于 Apksigner。
  let mut zip_pos = -1
  let mut sign_pos = -1
  for i in 0..<plan.steps.length() {
    if step_label(plan.steps[i]) == "Zipalign" {
      zip_pos = i
    }
    if step_label(plan.steps[i]) == "Apksigner" {
      sign_pos = i
    }
  }
  assert_true(zip_pos >= 0 && sign_pos >= 0 && zip_pos < sign_pos)
  // 最终 APK 产物 = Apksigner 步骤输出。
  @test.assert_eq(plan.outputs[sign_pos], "com.example.app.apk")
}

///|
test "plan_build abis 为空时回落 config.abis" {
  let config = demo_config()
  let plan = @moon_android.plan_build(config, [])
  @test.assert_eq(plan.config.abis.length(), 1)
  @test.assert_eq(abi_label(plan.config.abis[0]), "arm64-v8a")
}

///|
test "plan_build abis 参数非空时覆盖 config.abis" {
  let config = demo_config()
  let plan = @moon_android.plan_build(config, [
    @moon_android.Abi::ArmeabiV7a,
    @moon_android.Abi::X86,
  ])
  @test.assert_eq(plan.config.abis.length(), 2)
  @test.assert_eq(abi_label(plan.config.abis[0]), "armeabi-v7a")
  @test.assert_eq(abi_label(plan.config.abis[1]), "x86")
  // 输入配置不被修改（纯函数）。
  @test.assert_eq(config.abis.length(), 1)
  @test.assert_eq(abi_label(config.abis[0]), "arm64-v8a")
}

///|
test "plan_build 与 render_script 确定性：双次调用逐字一致" {
  let config = demo_config()
  let p1 = @moon_android.plan_build(config, [@moon_android.Abi::X86])
  let p2 = @moon_android.plan_build(config, [@moon_android.Abi::X86])
  @test.assert_eq(
    @moon_android.render_script(p1),
    @moon_android.render_script(p1),
  )
  @test.assert_eq(
    @moon_android.render_script(p1),
    @moon_android.render_script(p2),
  )
}

///|
test "plan_build 非法包名一律 InvalidPackage" {
  let bad_names = [
    "", "app", "com.", ".com.app", "com..app", "com.1app.app", "com.app!.x", "com.app x",
    "com.-app.app", "1com.app",
  ]
  for bad in bad_names {
    let config : @moon_android.BuildConfig = {
      package_id: { name: bad, },
      activity: @moon_android.ActivityKind::NativeOnly,
      entry_url: None,
      abis: [@moon_android.Abi::Arm64V8a],
      min_sdk: 24,
      target_sdk: 34,
      signing_schemes: [@moon_android.SigningScheme::V2],
      keystore_ref: "@keys/release.jks",
      profile: @moon_android.BuildProfile::Release,
      toolchain: locked_toolchain(),
      extra_native_libs: [],
    }
    match @test.expect_error(() => @moon_android.plan_build(config, [])) {
      InvalidPackage(name) => @test.assert_eq(name, bad)
      _ => fail("expected InvalidPackage for " + bad)
    }
  }
}

///|
test "plan_build 合法包名样例通过" {
  let good_names = [
    "com.example.app", "a.b", "com.example.app2", "a.b_c", "Com.Example.App9",
  ]
  for good in good_names {
    let config : @moon_android.BuildConfig = {
      package_id: { name: good, },
      activity: @moon_android.ActivityKind::NativeOnly,
      entry_url: None,
      abis: [@moon_android.Abi::Arm64V8a],
      min_sdk: 24,
      target_sdk: 34,
      signing_schemes: [@moon_android.SigningScheme::V2],
      keystore_ref: "@keys/release.jks",
      profile: @moon_android.BuildProfile::Release,
      toolchain: locked_toolchain(),
      extra_native_libs: [],
    }
    let plan = @moon_android.plan_build(config, [])
    @test.assert_eq(plan.steps.length(), 10)
  }
}

///|
test "plan_build 版本锁缺失 → ToolchainNotLocked（逐字段）" {
  let base = locked_toolchain()
  let unlocked : Array[@moon_android.ToolchainVersions] = [
    { ..base, moon_cli: "", },
    { ..base, moonc: "", },
    { ..base, core: "", },
    { ..base, ndk: "", },
    { ..base, build_tools: "", },
    { ..base, platform: "", },
    { ..base, jdk: "", },
  ]
  let expected_fields = [
    "moon_cli", "moonc", "core", "ndk", "build_tools", "platform", "jdk",
  ]
  for i in 0..<unlocked.length() {
    let config : @moon_android.BuildConfig = {
      package_id: { name: "com.example.app", },
      activity: @moon_android.ActivityKind::NativeOnly,
      entry_url: None,
      abis: [@moon_android.Abi::Arm64V8a],
      min_sdk: 24,
      target_sdk: 34,
      signing_schemes: [@moon_android.SigningScheme::V2],
      keystore_ref: "@keys/release.jks",
      profile: @moon_android.BuildProfile::Release,
      toolchain: unlocked[i],
      extra_native_libs: [],
    }
    match @test.expect_error(() => @moon_android.plan_build(config, [])) {
      ToolchainNotLocked(field) => @test.assert_eq(field, expected_fields[i])
      _ => fail("expected ToolchainNotLocked for " + expected_fields[i])
    }
  }
}

///|
test "plan_build cmake 缺失 → MissingTool（CrossCompile 需要 cmake）" {
  let base = locked_toolchain()
  for cmake in [None, Some("")] {
    let config : @moon_android.BuildConfig = {
      package_id: { name: "com.example.app", },
      activity: @moon_android.ActivityKind::NativeOnly,
      entry_url: None,
      abis: [@moon_android.Abi::Arm64V8a],
      min_sdk: 24,
      target_sdk: 34,
      signing_schemes: [@moon_android.SigningScheme::V2],
      keystore_ref: "@keys/release.jks",
      profile: @moon_android.BuildProfile::Release,
      toolchain: { ..base, cmake, },
      extra_native_libs: [],
    }
    match @test.expect_error(() => @moon_android.plan_build(config, [])) {
      MissingTool(name) => @test.assert_eq(name, "cmake")
      _ => fail("expected MissingTool(cmake)")
    }
  }
}

///|
test "plan_build 密钥内嵌 → KeyMaterialEmbedded" {
  let bad_refs = [
    "-----BEGIN PRIVATE KEY-----\nMII...", "-----begin certificate-----", "keystore.jks?storepass=secret",
    "KEYPASS=hunter2", "data:application/octet-stream;base64,MIICdwIBADANBg",
  ]
  for bad in bad_refs {
    let config : @moon_android.BuildConfig = {
      package_id: { name: "com.example.app", },
      activity: @moon_android.ActivityKind::NativeOnly,
      entry_url: None,
      abis: [@moon_android.Abi::Arm64V8a],
      min_sdk: 24,
      target_sdk: 34,
      signing_schemes: [@moon_android.SigningScheme::V2],
      keystore_ref: bad,
      profile: @moon_android.BuildProfile::Release,
      toolchain: locked_toolchain(),
      extra_native_libs: [],
    }
    match @test.expect_error(() => @moon_android.plan_build(config, [])) {
      KeyMaterialEmbedded => ()
      _ => fail("expected KeyMaterialEmbedded for " + bad)
    }
  }
}

///|
test "plan_build 合法 keystore_ref 只存引用、正常通过" {
  for
    ref_ in [
      "@keys/release.jks", "file:relative/path.jks", "secret-store://alias/release",
    ] {
    let config : @moon_android.BuildConfig = {
      package_id: { name: "com.example.app", },
      activity: @moon_android.ActivityKind::NativeOnly,
      entry_url: None,
      abis: [@moon_android.Abi::Arm64V8a],
      min_sdk: 24,
      target_sdk: 34,
      signing_schemes: [@moon_android.SigningScheme::V2],
      keystore_ref: ref_,
      profile: @moon_android.BuildProfile::Release,
      toolchain: locked_toolchain(),
      extra_native_libs: [],
    }
    let plan = @moon_android.plan_build(config, [])
    @test.assert_eq(plan.config.keystore_ref, ref_)
  }
}

///|
test "plan_build 签名方案冲突 → SigningSchemeConflict" {
  let base = demo_config()
  let cases : Array[@moon_android.BuildConfig] = [
    { ..base, signing_schemes: [], },
    {
      ..base,
      signing_schemes: [
        @moon_android.SigningScheme::V2,
        @moon_android.SigningScheme::V2,
      ],
    },
    { ..base, min_sdk: 21, signing_schemes: [@moon_android.SigningScheme::V2], },
    {
      ..base,
      signing_schemes: [
        @moon_android.SigningScheme::V31,
        @moon_android.SigningScheme::V2,
      ],
    },
  ]
  let expected_hints = ["为空", "重复", "V1", "V31"]
  for i in 0..<cases.length() {
    match @test.expect_error(() => @moon_android.plan_build(cases[i], [])) {
      SigningSchemeConflict(msg) =>
        assert_true(msg.contains(expected_hints[i]), msg~)
      _ => fail("expected SigningSchemeConflict for case \{i}")
    }
  }
}

///|
test "plan_build ABI 集为空或重复 → UnsupportedAbi" {
  let base = demo_config()
  match
    @test.expect_error(() => @moon_android.plan_build({ ..base, abis: [], }, [])) {
    UnsupportedAbi(name) => @test.assert_eq(name, "none")
    _ => fail("expected UnsupportedAbi(none)")
  }
  match
    @test.expect_error(() => {
      @moon_android.plan_build(base, [
        @moon_android.Abi::X86,
        @moon_android.Abi::X86,
      ])
    }) {
    UnsupportedAbi(name) => @test.assert_eq(name, "x86")
    _ => fail("expected UnsupportedAbi(x86)")
  }
}

///|
test "render_script 双次渲染逐字一致（确定性）" {
  let plan = @moon_android.plan_build(demo_config(), [])
  let first = @moon_android.render_script(plan)
  let second = @moon_android.render_script(plan)
  @test.assert_eq(first, second)
  assert_true(first.contains("#!/bin/sh"))
}

///|
test "render_script golden：确定性脚本文本快照" {
  let plan = @moon_android.plan_build(demo_config(), [
    @moon_android.Abi::Arm64V8a,
    @moon_android.Abi::ArmeabiV7a,
  ])
  inspect(
    @moon_android.render_script(plan),
    content=(
      #|#!/bin/sh
      #|# rendered by moon_android::render_script — deterministic review artifact; DO NOT EXECUTE
      #|# package_id: com.example.app
      #|# activity: WebView
      #|# entry_url: https://example.com/index.html
      #|# profile: debug
      #|# min_sdk: 24
      #|# target_sdk: 34
      #|# abis: arm64-v8a, armeabi-v7a
      #|# signing_schemes: V2, V3
      #|# keystore_ref: @keys/release.jks
      #|# toolchain.moon_cli: moon 0.1.20261104
      #|# toolchain.moonc: v0.10.20+65efd5b93
      #|# toolchain.core: 0.1.0
      #|# toolchain.ndk: r27
      #|# toolchain.build_tools: 34.0.0
      #|# toolchain.platform: android-34
      #|# toolchain.jdk: 17
      #|# toolchain.cmake: 3.22.1
      #|# step order contract: CrossCompile -> Aapt2Compile -> Aapt2Link -> Javac -> D8
      #|#   -> Assemble -> Zipalign -> Apksigner -> Verify -> AdbInstall
      #|
      #|# [1/10] CrossCompile
      #|#   in: src/native/stub.c -> out: libapp.so
      #|#   tools: cmake@3.22.1, ndk@r27
      #|$CMAKE -S src/native -B out/native/arm64-v8a -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-34 -DCMAKE_TOOLCHAIN_FILE=$NDK_ROOT/build/cmake/android.toolchain.cmake
      #|$CMAKE --build out/native/arm64-v8a --target libapp.so
      #|$CMAKE -S src/native -B out/native/armeabi-v7a -DANDROID_ABI=armeabi-v7a -DANDROID_PLATFORM=android-34 -DCMAKE_TOOLCHAIN_FILE=$NDK_ROOT/build/cmake/android.toolchain.cmake
      #|$CMAKE --build out/native/armeabi-v7a --target libapp.so
      #|
      #|# [2/10] Aapt2Compile
      #|#   in: res/ -> out: com.example.app.flat
      #|#   tools: aapt2@34.0.0
      #|$AAPT2 compile --dir res -o com.example.app.flat
      #|
      #|# [3/10] Aapt2Link
      #|#   in: com.example.app.flat -> out: com.example.app.res.apk
      #|#   tools: aapt2@34.0.0, android.jar@android-34
      #|$AAPT2 link -o com.example.app.res.apk -I $ANDROID_JAR --manifest AndroidManifest.xml com.example.app.flat
      #|
      #|# [4/10] Javac
      #|#   in: gen/ -> out: com.example.app.classes
      #|#   tools: javac@17, android.jar@android-34
      #|$JAVAC -classpath $ANDROID_JAR -d com.example.app.classes gen/*.java src/java/*.java
      #|
      #|# [5/10] D8
      #|#   in: com.example.app.classes -> out: classes.dex
      #|#   tools: d8@34.0.0
      #|$D8 --debug --min-api 24 --output classes.dex com.example.app.classes
      #|
      #|# [6/10] Assemble
      #|#   in: classes.dex -> out: com.example.app-unsigned.apk
      #|#   tools: jar@17
      #|cp com.example.app.res.apk com.example.app-unsigned.apk && $JAR uf com.example.app-unsigned.apk classes.dex
      #|mkdir -p out/native/arm64-v8a/lib/arm64-v8a && cp out/native/arm64-v8a/libapp.so out/native/arm64-v8a/lib/arm64-v8a/libapp.so
      #|$JAR uf com.example.app-unsigned.apk -C out/native/arm64-v8a lib/arm64-v8a/libapp.so
      #|mkdir -p out/native/armeabi-v7a/lib/armeabi-v7a && cp out/native/armeabi-v7a/libapp.so out/native/armeabi-v7a/lib/armeabi-v7a/libapp.so
      #|$JAR uf com.example.app-unsigned.apk -C out/native/armeabi-v7a lib/armeabi-v7a/libapp.so
      #|
      #|# [7/10] Zipalign
      #|#   in: com.example.app-unsigned.apk -> out: com.example.app-aligned.apk
      #|#   tools: zipalign@34.0.0
      #|$ZIPALIGN -p -f 4 com.example.app-unsigned.apk com.example.app-aligned.apk
      #|
      #|# [8/10] Apksigner
      #|#   in: com.example.app-aligned.apk -> out: com.example.app.apk
      #|#   tools: apksigner@34.0.0
      #|$APKSIGNER sign --ks "$KEYSTORE_REF" --v2-signing-enabled true --v3-signing-enabled true --out com.example.app.apk com.example.app-aligned.apk
      #|
      #|# [9/10] Verify
      #|#   in: com.example.app.apk -> out: com.example.app.verify.txt
      #|#   tools: apksigner@34.0.0
      #|$APKSIGNER verify --print-certs com.example.app.apk > com.example.app.verify.txt
      #|
      #|# [10/10] AdbInstall
      #|#   in: com.example.app.apk -> out: device/com.example.app.apk
      #|#   tools: adb@device-side
      #|$ADB install -r com.example.app.apk
      #|
      #|# end of plan: 10 steps; moon_android never executes this script
      #|
    ),
  )
}

///|
test "render_script 内容含步骤标记、工具版本且不泄漏密钥" {
  let plan = @moon_android.plan_build(demo_config(), [])
  let text = @moon_android.render_script(plan)
  assert_true(text.contains("# [1/10] CrossCompile"))
  assert_true(text.contains("# [7/10] Zipalign"))
  assert_true(text.contains("# [8/10] Apksigner"))
  assert_true(text.contains("# [10/10] AdbInstall"))
  assert_true(text.contains("toolchain.moon_cli: moon 0.1.20261104"))
  assert_true(text.contains("toolchain.build_tools: 34.0.0"))
  assert_true(text.contains("--min-api 24"))
  assert_true(text.contains("--v2-signing-enabled true"))
  assert_true(text.contains("--v3-signing-enabled true"))
  assert_true(text.contains("$KEYSTORE_REF"))
  assert_true(text.contains("@keys/release.jks"))
  assert_true(!text.contains("-----BEGIN"))
  // 步骤标记按规范顺序递增。
  let pos_zip = text.find("# [7/10]").unwrap()
  let pos_sign = text.find("# [8/10]").unwrap()
  assert_true(pos_zip < pos_sign)
}

///|
test "render_script 步骤顺序非法 → InvalidStepOrder" {
  let plan = raw_plan(
    [@moon_android.BuildStep::Apksigner, @moon_android.BuildStep::Zipalign],
    demo_config(),
  )
  match @test.expect_error(() => @moon_android.render_script(plan)) {
    InvalidStepOrder(first, second) => {
      @test.assert_eq(first, "Apksigner")
      @test.assert_eq(second, "Zipalign")
    }
    _ => fail("expected InvalidStepOrder")
  }
}

///|
test "render_script 缺工具 → MissingTool" {
  let base = locked_toolchain()
  // CrossCompile 需要 cmake。
  let no_cmake : @moon_android.BuildConfig = {
    ..demo_config(),
    toolchain: { ..base, cmake: None, },
  }
  match
    @test.expect_error(() => {
      @moon_android.render_script(
        raw_plan([@moon_android.BuildStep::CrossCompile], no_cmake),
      )
    }) {
    MissingTool(name) => @test.assert_eq(name, "cmake")
    _ => fail("expected MissingTool(cmake)")
  }
  // Aapt2Compile 需要 build_tools 提供 aapt2。
  let no_build_tools : @moon_android.BuildConfig = {
    ..demo_config(),
    toolchain: { ..base, build_tools: "", },
  }
  match
    @test.expect_error(() => {
      @moon_android.render_script(
        raw_plan([@moon_android.BuildStep::Aapt2Compile], no_build_tools),
      )
    }) {
    MissingTool(name) => @test.assert_eq(name, "aapt2")
    _ => fail("expected MissingTool(aapt2)")
  }
}

///|
test "render_script 密钥内嵌 → KeyMaterialEmbedded（绝不把密钥渲染进文本）" {
  let base = demo_config()
  let leaked : @moon_android.BuildConfig = {
    ..base,
    keystore_ref: "-----BEGIN PRIVATE KEY-----\nMII...",
  }
  match
    @test.expect_error(() => {
      @moon_android.render_script(
        raw_plan([@moon_android.BuildStep::AdbInstall], leaked),
      )
    }) {
    KeyMaterialEmbedded => ()
    _ => fail("expected KeyMaterialEmbedded")
  }
}

///|
test "verify_artifact 元数据一致 → true" {
  let plan = @moon_android.plan_build(demo_config(), [])
  let artifact : @moon_android.Artifact = {
    path: "com.example.app.apk",
    size_bytes: 1024UL,
    sha256: good_sha256(),
    abis: [@moon_android.Abi::Arm64V8a],
    signatures: [
      @moon_android.SigningScheme::V2,
      @moon_android.SigningScheme::V3,
    ],
  }
  assert_true(@moon_android.verify_artifact(plan, artifact))
}

///|
test "verify_artifact ABI/签名集合不符 → false" {
  let plan = @moon_android.plan_build(demo_config(), [])
  let wrong_abi : @moon_android.Artifact = {
    path: "com.example.app.apk",
    size_bytes: 1024UL,
    sha256: good_sha256(),
    abis: [@moon_android.Abi::X86],
    signatures: [
      @moon_android.SigningScheme::V2,
      @moon_android.SigningScheme::V3,
    ],
  }
  assert_true(!@moon_android.verify_artifact(plan, wrong_abi))
  let wrong_scheme : @moon_android.Artifact = {
    path: "com.example.app.apk",
    size_bytes: 1024UL,
    sha256: good_sha256(),
    abis: [@moon_android.Abi::Arm64V8a],
    signatures: [@moon_android.SigningScheme::V2],
  }
  assert_true(!@moon_android.verify_artifact(plan, wrong_scheme))
}

///|
test "verify_artifact 路径与计划不符 → ArtifactMismatch" {
  let plan = @moon_android.plan_build(demo_config(), [])
  let artifact : @moon_android.Artifact = {
    path: "other.apk",
    size_bytes: 1024UL,
    sha256: good_sha256(),
    abis: [@moon_android.Abi::Arm64V8a],
    signatures: [
      @moon_android.SigningScheme::V2,
      @moon_android.SigningScheme::V3,
    ],
  }
  match
    @test.expect_error(() => @moon_android.verify_artifact(plan, artifact)) {
    ArtifactMismatch(msg) => assert_true(msg.contains("路径"), msg~)
    _ => fail("expected ArtifactMismatch")
  }
}

///|
test "verify_artifact 空产物或 sha256 非法 → ArtifactMismatch" {
  let plan = @moon_android.plan_build(demo_config(), [])
  let empty_size : @moon_android.Artifact = {
    path: "com.example.app.apk",
    size_bytes: 0UL,
    sha256: good_sha256(),
    abis: [@moon_android.Abi::Arm64V8a],
    signatures: [
      @moon_android.SigningScheme::V2,
      @moon_android.SigningScheme::V3,
    ],
  }
  match
    @test.expect_error(() => @moon_android.verify_artifact(plan, empty_size)) {
    ArtifactMismatch(msg) => assert_true(msg.contains("size_bytes"), msg~)
    _ => fail("expected ArtifactMismatch(size)")
  }
  for
    bad_sha in [
      "", "zz", "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcde",
    ] {
    let bad : @moon_android.Artifact = {
      path: "com.example.app.apk",
      size_bytes: 1024UL,
      sha256: bad_sha,
      abis: [@moon_android.Abi::Arm64V8a],
      signatures: [
        @moon_android.SigningScheme::V2,
        @moon_android.SigningScheme::V3,
      ],
    }
    match @test.expect_error(() => @moon_android.verify_artifact(plan, bad)) {
      ArtifactMismatch(msg) => assert_true(msg.contains("sha256"), msg~)
      _ => fail("expected ArtifactMismatch(sha256)")
    }
  }
}

///|
test "verify_artifact ABI/签名记录为空 → ArtifactMismatch" {
  let plan = @moon_android.plan_build(demo_config(), [])
  let no_abi : @moon_android.Artifact = {
    path: "com.example.app.apk",
    size_bytes: 1024UL,
    sha256: good_sha256(),
    abis: [],
    signatures: [
      @moon_android.SigningScheme::V2,
      @moon_android.SigningScheme::V3,
    ],
  }
  match @test.expect_error(() => @moon_android.verify_artifact(plan, no_abi)) {
    ArtifactMismatch(msg) => assert_true(msg.contains("ABI"), msg~)
    _ => fail("expected ArtifactMismatch(ABI)")
  }
  let no_scheme : @moon_android.Artifact = {
    path: "com.example.app.apk",
    size_bytes: 1024UL,
    sha256: good_sha256(),
    abis: [@moon_android.Abi::Arm64V8a],
    signatures: [],
  }
  match
    @test.expect_error(() => @moon_android.verify_artifact(plan, no_scheme)) {
    ArtifactMismatch(msg) => assert_true(msg.contains("签名"), msg~)
    _ => fail("expected ArtifactMismatch(签名)")
  }
}

///|
test "verify_artifact 计划缺 Apksigner 或产物名 → ArtifactMismatch" {
  let artifact : @moon_android.Artifact = {
    path: "com.example.app.apk",
    size_bytes: 1024UL,
    sha256: good_sha256(),
    abis: [@moon_android.Abi::Arm64V8a],
    signatures: [@moon_android.SigningScheme::V2],
  }
  let no_signer = raw_plan([@moon_android.BuildStep::Zipalign], demo_config())
  match
    @test.expect_error(() => @moon_android.verify_artifact(no_signer, artifact)) {
    ArtifactMismatch(msg) => assert_true(msg.contains("Apksigner"), msg~)
    _ => fail("expected ArtifactMismatch(no Apksigner)")
  }
  let no_output = raw_plan([@moon_android.BuildStep::Apksigner], demo_config())
  match
    @test.expect_error(() => @moon_android.verify_artifact(no_output, artifact)) {
    ArtifactMismatch(msg) => assert_true(msg.contains("产物名"), msg~)
    _ => fail("expected ArtifactMismatch(no outputs)")
  }
}

///|
test "ci_gate_plan 七项门禁、含 CheckDenyWarn、顺序固定" {
  let gates = @moon_android.ci_gate_plan()
  @test.assert_eq(gates.length(), 7)
  let labels : Array[String] = []
  for gate in gates {
    labels.push(gate_label(gate))
  }
  @test.assert_eq(
    join_labels(labels),
    "FmtCheck, Check, CheckDenyWarn, TestCoverage, Bench, InfoSnapshot, VersionLock",
  )
}
