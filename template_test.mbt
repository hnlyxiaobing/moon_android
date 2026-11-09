// 通用模板黑盒测试：参数化、生成目录树、脚本渲染与错误路径。

///|
/// 双 ABI 模板配置（WebView 壳、V2+V3 签名、版本锁齐备）。
fn template_config() -> @moon_android.BuildConfig {
  {
    package_id: { name: "com.example.app", },
    activity: @moon_android.ActivityKind::WebView,
    entry_url: Some("https://example.com/index.html?a=1&b=2"),
    abis: [@moon_android.Abi::Arm64V8a, @moon_android.Abi::ArmeabiV7a],
    min_sdk: 24,
    target_sdk: 34,
    signing_schemes: [
      @moon_android.SigningScheme::V2,
      @moon_android.SigningScheme::V3,
    ],
    keystore_ref: "@keys/release.jks",
    profile: @moon_android.BuildProfile::Release,
    toolchain: locked_toolchain(),
    extra_native_libs: [],
  }
}

///|
/// 模板样例：1 个模块依赖 + 1 个资产。
fn demo_template() -> @moon_android.TemplateParams {
  {
    config: template_config(),
    app_name: "Demo App",
    module_deps: ["hnlyxiaobing/moon_abi"],
    assets: [
      { source: "web/index.html", target: "index.html", sha256: good_sha256(), },
    ],
  }
}

///|
/// 生成文件种类 → 名称标签。
fn kind_label(kind : @moon_android.GeneratedKind) -> String {
  match kind {
    @moon_android.GeneratedKind::ManifestXml => "ManifestXml"
    @moon_android.GeneratedKind::StringsXml => "StringsXml"
    @moon_android.GeneratedKind::NativeBuild => "NativeBuild"
    @moon_android.GeneratedKind::ModuleDeps => "ModuleDeps"
    @moon_android.GeneratedKind::AbiManifest => "AbiManifest"
    @moon_android.GeneratedKind::AssetManifest => "AssetManifest"
  }
}

///|
/// 取生成树中指定路径的文件内容（不存在则 fail）。
fn file_content(tree : @moon_android.GeneratedTree, path : String) -> String {
  for file in tree.files {
    if file.path == path {
      return file.content
    }
  }
  abort("missing generated file: " + path)
}

///|
test "plan_template 生成目录树：6 个文件、顺序与内容映射" {
  let tree = @moon_android.plan_template(demo_template())
  @test.assert_eq(tree.root, "build/android")
  @test.assert_eq(tree.app_name, "Demo App")
  @test.assert_eq(tree.files.length(), 6)
  let paths : Array[String] = []
  let kinds : Array[String] = []
  for file in tree.files {
    paths.push(file.path)
    kinds.push(kind_label(file.kind))
  }
  @test.assert_eq(
    join_labels(paths),
    "AndroidManifest.xml, res/values/strings.xml, src/native/CMakeLists.txt, plan/module-deps.txt, plan/abi-libs.txt, plan/assets.txt",
  )
  @test.assert_eq(
    join_labels(kinds),
    "ManifestXml, StringsXml, NativeBuild, ModuleDeps, AbiManifest, AssetManifest",
  )
  // BuildPlan 仍是规范 10 步。
  @test.assert_eq(tree.build_plan.steps.length(), 10)
  // 双 ABI 布局（无哈希、目录与 soname 正确）。
  @test.assert_eq(tree.native_libs.length(), 2)
  @test.assert_eq(tree.native_libs[0].dir, "arm64-v8a")
  @test.assert_eq(tree.native_libs[1].dir, "armeabi-v7a")
  @test.assert_eq(tree.native_libs[0].soname, "libapp.so")
  assert_true(tree.native_libs[0].sha256 is None)
}

///|
test "plan_template Manifest / strings / CMake / 清单内容" {
  let tree = @moon_android.plan_template(demo_template())
  let manifest = file_content(tree, "AndroidManifest.xml")
  assert_true(manifest.contains("package=\"com.example.app\""))
  assert_true(manifest.contains("android:minSdkVersion=\"24\""))
  assert_true(manifest.contains("android:targetSdkVersion=\"34\""))
  assert_true(manifest.contains(".MoonWebViewActivity"))
  // entry_url 中的 & 必须转义，不能原样进入 XML。
  assert_true(manifest.contains("a=1&amp;b=2"))
  assert_true(!manifest.contains("a=1&b=2"))
  let strings = file_content(tree, "res/values/strings.xml")
  assert_true(strings.contains("name=\"app_name\">Demo App</string>"))
  let cmake = file_content(tree, "src/native/CMakeLists.txt")
  assert_true(cmake.contains("set(MOON_ANDROID_SONAME \"libapp.so\")"))
  assert_true(cmake.contains("cmake_minimum_required(VERSION 3.22.1)"))
  assert_true(cmake.contains("add_library(libapp.so SHARED stub.c)"))
  assert_true(cmake.contains("OUTPUT_NAME \"app\""))
  assert_true(cmake.contains("target_link_libraries(libapp.so log)"))
  let deps = file_content(tree, "plan/module-deps.txt")
  assert_true(deps.contains("# count: 1"))
  assert_true(deps.contains("hnlyxiaobing/moon_abi"))
  let abi_libs = file_content(tree, "plan/abi-libs.txt")
  assert_true(
    abi_libs.contains("arm64-v8a libapp.so -> lib/arm64-v8a/libapp.so"),
  )
  assert_true(
    abi_libs.contains("armeabi-v7a libapp.so -> lib/armeabi-v7a/libapp.so"),
  )
  let assets = file_content(tree, "plan/assets.txt")
  assert_true(
    assets.contains("index.html <- web/index.html sha256=" + good_sha256()),
  )
}

///|
test "plan_template 空模块依赖与嵌套资产目标" {
  let params : @moon_android.TemplateParams = {
    config: template_config(),
    app_name: "红米电视 Demo",
    module_deps: [],
    assets: [
      { source: "web/a.html", target: "web/a.html", sha256: good_sha256(), },
      { source: "web/b.css", target: "web/b.css", sha256: second_sha256(), },
    ],
  }
  let tree = @moon_android.plan_template(params)
  let deps = file_content(tree, "plan/module-deps.txt")
  assert_true(deps.contains("# count: 0"))
  assert_true(deps.contains("# (none)"))
  assert_true(
    file_content(tree, "res/values/strings.xml").contains("红米电视 Demo"),
  )
  let assets = file_content(tree, "plan/assets.txt")
  assert_true(assets.contains("web/a.html <- web/a.html"))
  assert_true(assets.contains("web/b.css <- web/b.css"))
}

///|
test "plan_template XML 转义：应用名与 entry_url 的 5 个特殊字符" {
  let params : @moon_android.TemplateParams = {
    config: {
      ..template_config(),
      entry_url: Some("https://e.test/?q=<x>&y=\"z\"'"),
    },
    app_name: "A & B <C> \"D\" 'E'",
    module_deps: [],
    assets: [],
  }
  let tree = @moon_android.plan_template(params)
  let strings = file_content(tree, "res/values/strings.xml")
  assert_true(
    strings.contains("A &amp; B &lt;C&gt; &quot;D&quot; &apos;E&apos;"),
  )
  let manifest = file_content(tree, "AndroidManifest.xml")
  assert_true(manifest.contains("q=&lt;x&gt;&amp;y=&quot;z&quot;&apos;"))
}

///|
test "plan_template 非法 app_name → InvalidTemplate" {
  let too_long = "abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmnopqrstuvwxyz0123456789abcd"
  assert_true(too_long.length() > 64)
  for bad in ["", "   ", "line\nbreak", "tab\there", too_long] {
    let params : @moon_android.TemplateParams = {
      ..demo_template(),
      app_name: bad,
    }
    match @test.expect_error(() => @moon_android.plan_template(params)) {
      InvalidTemplate(msg) => assert_true(msg.contains("app_name"), msg~)
      _ => fail("expected InvalidTemplate(app_name)")
    }
  }
  // 64 字符边界可通过。
  let exactly64 = "abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmnopqrstuvwxyzab"
  @test.assert_eq(exactly64.length(), 64)
  let params : @moon_android.TemplateParams = {
    ..demo_template(),
    app_name: exactly64,
  }
  let tree = @moon_android.plan_template(params)
  @test.assert_eq(tree.app_name, exactly64)
}

///|
test "plan_template 非法 / 重复 module_deps → InvalidTemplate" {
  for bad in ["", "../evil", "a//b", "a/./b", "a/../b", "/abs", "has space"] {
    let params : @moon_android.TemplateParams = {
      ..demo_template(),
      module_deps: [bad],
    }
    match @test.expect_error(() => @moon_android.plan_template(params)) {
      InvalidTemplate(msg) => assert_true(msg.contains("module_dep"), msg~)
      _ => fail("expected InvalidTemplate(module_dep) for " + bad)
    }
  }
  let dup : @moon_android.TemplateParams = {
    ..demo_template(),
    module_deps: ["hnlyxiaobing/moon_abi", "hnlyxiaobing/moon_abi"],
  }
  match @test.expect_error(() => @moon_android.plan_template(dup)) {
    InvalidTemplate(msg) => assert_true(msg.contains("重复"), msg~)
    _ => fail("expected InvalidTemplate(duplicate module_dep)")
  }
  // 合法变体：带版本号 / 单段名。
  let ok : @moon_android.TemplateParams = {
    ..demo_template(),
    module_deps: ["hnlyxiaobing/moon_abi", "bobzhang/zip@0.1.2", "moon_android"],
  }
  @test.assert_eq(@moon_android.plan_template(ok).files.length(), 6)
}

///|
test "plan_template 非法资产声明 → InvalidAsset" {
  let bad_sources = ["", "/abs/a", "../a", "a\\b", "a b", "a//b"]
  for bad in bad_sources {
    let params : @moon_android.TemplateParams = {
      ..demo_template(),
      assets: [{ source: bad, target: "a.txt", sha256: good_sha256(), }],
    }
    match @test.expect_error(() => @moon_android.plan_template(params)) {
      InvalidAsset(msg) => assert_true(msg.contains("source"), msg~)
      _ => fail("expected InvalidAsset(source) for " + bad)
    }
  }
  let bad_targets = ["", "/abs", "../evil", "a\\b", "a b", "a//b", "a/"]
  for bad in bad_targets {
    let params : @moon_android.TemplateParams = {
      ..demo_template(),
      assets: [{ source: "web/a", target: bad, sha256: good_sha256(), }],
    }
    match @test.expect_error(() => @moon_android.plan_template(params)) {
      InvalidAsset(msg) => assert_true(msg.contains("target"), msg~)
      _ => fail("expected InvalidAsset(target) for " + bad)
    }
  }
  // 非法哈希。
  let params : @moon_android.TemplateParams = {
    ..demo_template(),
    assets: [{ source: "web/a", target: "a", sha256: "not-a-hash", }],
  }
  match @test.expect_error(() => @moon_android.plan_template(params)) {
    InvalidAsset(msg) => assert_true(msg.contains("sha256"), msg~)
    _ => fail("expected InvalidAsset(sha256)")
  }
  // 重复 target。
  let dup : @moon_android.TemplateParams = {
    ..demo_template(),
    assets: [
      { source: "web/a", target: "same.txt", sha256: good_sha256(), },
      { source: "web/b", target: "same.txt", sha256: second_sha256(), },
    ],
  }
  match @test.expect_error(() => @moon_android.plan_template(dup)) {
    InvalidAsset(msg) => assert_true(msg.contains("重复"), msg~)
    _ => fail("expected InvalidAsset(duplicate target)")
  }
}

///|
test "plan_template 配置错误原样传播（包名/版本锁/密钥/ABI）" {
  let bad_pkg : @moon_android.TemplateParams = {
    ..demo_template(),
    config: { ..template_config(), package_id: { name: "1bad", }, },
  }
  match @test.expect_error(() => @moon_android.plan_template(bad_pkg)) {
    InvalidPackage(name) => @test.assert_eq(name, "1bad")
    _ => fail("expected InvalidPackage")
  }
  let unlocked : @moon_android.TemplateParams = {
    ..demo_template(),
    config: {
      ..template_config(),
      toolchain: { ..locked_toolchain(), jdk: "", },
    },
  }
  match @test.expect_error(() => @moon_android.plan_template(unlocked)) {
    ToolchainNotLocked(field) => @test.assert_eq(field, "jdk")
    _ => fail("expected ToolchainNotLocked")
  }
  let leaked : @moon_android.TemplateParams = {
    ..demo_template(),
    config: {
      ..template_config(),
      keystore_ref: "-----BEGIN PRIVATE KEY-----\nMII...",
    },
  }
  match @test.expect_error(() => @moon_android.plan_template(leaked)) {
    KeyMaterialEmbedded => ()
    _ => fail("expected KeyMaterialEmbedded")
  }
  let no_abi : @moon_android.TemplateParams = {
    ..demo_template(),
    config: { ..template_config(), abis: [], },
  }
  match @test.expect_error(() => @moon_android.plan_template(no_abi)) {
    UnsupportedAbi(name) => @test.assert_eq(name, "none")
    _ => fail("expected UnsupportedAbi(none)")
  }
}

///|
test "render_template_script 四阶段、确定性且不泄漏密钥" {
  let tree = @moon_android.plan_template(demo_template())
  let first = @moon_android.render_template_script(tree)
  let second = @moon_android.render_template_script(tree)
  @test.assert_eq(first, second)
  assert_true(first.contains("#!/bin/sh"))
  assert_true(first.contains("# template root: build/android"))
  assert_true(first.contains("# package_id: com.example.app"))
  assert_true(first.contains("# app_name: Demo App"))
  assert_true(first.contains("# abis: arm64-v8a, armeabi-v7a"))
  assert_true(
    first.contains("# --- 1/4 materialize generated tree (6 files) ---"),
  )
  assert_true(first.contains("# --- 2/4 ABI layout (2 dirs) ---"))
  assert_true(
    first.contains(
      "# --- 3/4 asset injection (1 assets; sha256 verified before copy) ---",
    ),
  )
  assert_true(first.contains("# --- 4/4 build plan (10 steps) ---"))
  // 构建计划前先进入模板根，使相对路径与生成目录树一致。
  assert_true(
    first.contains("# --- 4/4 build plan (10 steps) ---\ncd build/android"),
  )
  // 物化生成目录树：mkdir + heredoc。
  assert_true(first.contains("mkdir -p build/android"))
  assert_true(first.contains("mkdir -p build/android/res/values"))
  assert_true(first.contains("mkdir -p build/android/src/native"))
  assert_true(
    first.contains(
      "cat > build/android/AndroidManifest.xml <<'MOON_ANDROID_EOF_0'",
    ),
  )
  assert_true(
    first.contains(
      "cat > build/android/src/native/CMakeLists.txt <<'MOON_ANDROID_EOF_2'",
    ),
  )
  assert_true(
    first.contains("cat > build/android/plan/assets.txt <<'MOON_ANDROID_EOF_5'"),
  )
  // ABI 布局与期望 APK 条目。
  assert_true(first.contains("mkdir -p build/android/jniLibs/arm64-v8a"))
  assert_true(first.contains("mkdir -p build/android/jniLibs/armeabi-v7a"))
  assert_true(
    first.contains(
      "# expected APK entry: lib/arm64-v8a/libapp.so (sha256=unregistered)",
    ),
  )
  // 资产注入：先校验 SHA-256 再复制。
  assert_true(
    first.contains(
      "echo '" + good_sha256() + "  web/index.html' | sha256sum -c -",
    ),
  )
  assert_true(
    first.contains("cp 'web/index.html' 'build/android/assets/index.html'"),
  )
  // 构建计划仍由 10 步组成，且密钥只以引用出现。
  assert_true(first.contains("# [1/10] CrossCompile"))
  assert_true(first.contains("# [10/10] AdbInstall"))
  assert_true(first.contains("$KEYSTORE_REF"))
  assert_true(!first.contains("-----BEGIN"))
}

///|
test "render_template_script golden：单 ABI 模板脚本快照" {
  let params : @moon_android.TemplateParams = {
    config: {
      ..template_config(),
      activity: @moon_android.ActivityKind::NativeOnly,
      entry_url: None,
      abis: [@moon_android.Abi::Arm64V8a],
    },
    app_name: "Demo",
    module_deps: ["hnlyxiaobing/moon_abi"],
    assets: [
      { source: "web/index.html", target: "index.html", sha256: good_sha256(), },
    ],
  }
  inspect(
    @moon_android.render_template_script(@moon_android.plan_template(params)),
    content=(
      #|#!/bin/sh
      #|# rendered by moon_android::render_template_script — deterministic review artifact; DO NOT EXECUTE
      #|# template root: build/android
      #|# package_id: com.example.app
      #|# app_name: Demo
      #|# abis: arm64-v8a
      #|# generated files: 6
      #|# assets: 1
      #|
      #|# --- 1/4 materialize generated tree (6 files) ---
      #|mkdir -p build/android
      #|mkdir -p build/android/res/values
      #|mkdir -p build/android/src/native
      #|mkdir -p build/android/plan
      #|cat > build/android/AndroidManifest.xml <<'MOON_ANDROID_EOF_0'
      #|<?xml version="1.0" encoding="utf-8"?>
      #|<manifest xmlns:android="http://schemas.android.com/apk/res/android"
      #|    package="com.example.app">
      #|  <uses-sdk android:minSdkVersion="24" android:targetSdkVersion="34" />
      #|  <application android:label="@string/app_name" android:hasCode="true">
      #|    <activity android:name=".MoonNativeActivity" android:exported="true">
      #|      <intent-filter>
      #|        <action android:name="android.intent.action.MAIN" />
      #|        <category android:name="android.intent.category.LAUNCHER" />
      #|      </intent-filter>
      #|    </activity>
      #|  </application>
      #|</manifest>
      #|MOON_ANDROID_EOF_0
      #|cat > build/android/res/values/strings.xml <<'MOON_ANDROID_EOF_1'
      #|<?xml version="1.0" encoding="utf-8"?>
      #|<resources>
      #|  <string name="app_name">Demo</string>
      #|</resources>
      #|MOON_ANDROID_EOF_1
      #|cat > build/android/src/native/CMakeLists.txt <<'MOON_ANDROID_EOF_2'
      #|# generated by moon_android::plan_template — review artifact
      #|cmake_minimum_required(VERSION 3.22.1)
      #|project(moon_android_app C)
      #|set(MOON_ANDROID_SONAME "libapp.so")
      #|add_library(libapp.so SHARED stub.c)
      #|set_target_properties(libapp.so PROPERTIES
      #|  OUTPUT_NAME "app"
      #|  PREFIX "lib"
      #|  SUFFIX ".so")
      #|target_link_libraries(libapp.so log)
      #|MOON_ANDROID_EOF_2
      #|cat > build/android/plan/module-deps.txt <<'MOON_ANDROID_EOF_3'
      #|# generated by moon_android::plan_template — module deps (text contract)
      #|# moon_android never imports these modules; the composition root writes moon.pkg
      #|# count: 1
      #|hnlyxiaobing/moon_abi
      #|MOON_ANDROID_EOF_3
      #|cat > build/android/plan/abi-libs.txt <<'MOON_ANDROID_EOF_4'
      #|# generated by moon_android::plan_template — ABI layout
      #|# <abi dir> <soname> -> APK entry lib/<abi dir>/<soname>
      #|arm64-v8a libapp.so -> lib/arm64-v8a/libapp.so
      #|MOON_ANDROID_EOF_4
      #|cat > build/android/plan/assets.txt <<'MOON_ANDROID_EOF_5'
      #|# generated by moon_android::plan_template — asset injection registry
      #|# content is never stored by moon_android; sha256 is computed and verified by the composition root
      #|# target <- source sha256=<hex>
      #|index.html <- web/index.html sha256=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
      #|MOON_ANDROID_EOF_5
      #|
      #|# --- 2/4 ABI layout (1 dirs) ---
      #|mkdir -p build/android/jniLibs/arm64-v8a
      #|# expected APK entry: lib/arm64-v8a/libapp.so (sha256=unregistered)
      #|
      #|# --- 3/4 asset injection (1 assets; sha256 verified before copy) ---
      #|mkdir -p build/android/assets
      #|echo '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef  web/index.html' | sha256sum -c -
      #|cp 'web/index.html' 'build/android/assets/index.html'
      #|
      #|# --- 4/4 build plan (10 steps) ---
      #|cd build/android
      #|# rendered by moon_android::render_template_script — deterministic review artifact; DO NOT EXECUTE
      #|# package_id: com.example.app
      #|# activity: NativeOnly
      #|# entry_url: (none)
      #|# profile: release
      #|# min_sdk: 24
      #|# target_sdk: 34
      #|# abis: arm64-v8a
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
      #|$D8 --release --min-api 24 --output classes.dex com.example.app.classes
      #|
      #|# [6/10] Assemble
      #|#   in: classes.dex -> out: com.example.app-unsigned.apk
      #|#   tools: jar@17
      #|cp com.example.app.res.apk com.example.app-unsigned.apk && $JAR uf com.example.app-unsigned.apk classes.dex
      #|mkdir -p out/native/arm64-v8a/lib/arm64-v8a && cp out/native/arm64-v8a/libapp.so out/native/arm64-v8a/lib/arm64-v8a/libapp.so
      #|$JAR uf com.example.app-unsigned.apk -C out/native/arm64-v8a lib/arm64-v8a/libapp.so
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
test "render_template_script 嵌套资产目标创建父目录" {
  let params : @moon_android.TemplateParams = {
    ..demo_template(),
    assets: [
      { source: "web/js/app.js", target: "js/app.js", sha256: good_sha256(), },
    ],
  }
  let text = @moon_android.render_template_script(
    @moon_android.plan_template(params),
  )
  assert_true(text.contains("mkdir -p build/android/assets/js"))
  assert_true(
    text.contains("cp 'web/js/app.js' 'build/android/assets/js/app.js'"),
  )
}

///|
test "render_template_script 篡改树：非法/重复路径与分隔符注入 → InvalidTemplate" {
  let tree = @moon_android.plan_template(demo_template())
  // 非法相对路径（穿越）。
  let bad_path : @moon_android.GeneratedTree = {
    ..tree,
    files: [
      {
        path: "../escape.xml",
        kind: @moon_android.GeneratedKind::ManifestXml,
        content: "x\n",
      },
    ],
  }
  match
    @test.expect_error(() => @moon_android.render_template_script(bad_path)) {
    InvalidTemplate(msg) => assert_true(msg.contains("路径"), msg~)
    _ => fail("expected InvalidTemplate(path)")
  }
  // 重复路径。
  let dup : @moon_android.GeneratedTree = {
    ..tree,
    files: [
      {
        path: "a.txt",
        kind: @moon_android.GeneratedKind::ModuleDeps,
        content: "a\n",
      },
      {
        path: "a.txt",
        kind: @moon_android.GeneratedKind::ModuleDeps,
        content: "b\n",
      },
    ],
  }
  match @test.expect_error(() => @moon_android.render_template_script(dup)) {
    InvalidTemplate(msg) => assert_true(msg.contains("重复"), msg~)
    _ => fail("expected InvalidTemplate(duplicate path)")
  }
  // 内容含 heredoc 分隔符整行 → 拒绝渲染（防脚本注入）。
  let injected : @moon_android.GeneratedTree = {
    ..tree,
    files: [
      {
        path: "a.txt",
        kind: @moon_android.GeneratedKind::ModuleDeps,
        content: "ok\nMOON_ANDROID_EOF_0\nrm -rf /\n",
      },
    ],
  }
  match
    @test.expect_error(() => @moon_android.render_template_script(injected)) {
    InvalidTemplate(msg) => assert_true(msg.contains("分隔符"), msg~)
    _ => fail("expected InvalidTemplate(heredoc)")
  }
  // 非法根目录。
  let bad_root : @moon_android.GeneratedTree = { ..tree, root: "/abs", }
  match
    @test.expect_error(() => @moon_android.render_template_script(bad_root)) {
    InvalidTemplate(msg) => assert_true(msg.contains("根目录"), msg~)
    _ => fail("expected InvalidTemplate(root)")
  }
  // 非法 app_name（篡改）。
  let bad_app : @moon_android.GeneratedTree = { ..tree, app_name: "bad\nname", }
  match
    @test.expect_error(() => @moon_android.render_template_script(bad_app)) {
    InvalidTemplate(msg) => assert_true(msg.contains("app_name"), msg~)
    _ => fail("expected InvalidTemplate(app_name)")
  }
}

///|
test "render_template_script 篡改树：资产/密钥/工具错误路径" {
  let tree = @moon_android.plan_template(demo_template())
  let bad_asset : @moon_android.GeneratedTree = {
    ..tree,
    assets: [{ source: "../evil", target: "a", sha256: good_sha256(), }],
  }
  match
    @test.expect_error(() => @moon_android.render_template_script(bad_asset)) {
    InvalidAsset(msg) => assert_true(msg.contains("source"), msg~)
    _ => fail("expected InvalidAsset(source)")
  }
  let leaked : @moon_android.GeneratedTree = {
    ..tree,
    build_plan: raw_plan([@moon_android.BuildStep::Apksigner], {
      ..template_config(),
      keystore_ref: "storepass=secret",
    }),
  }
  match @test.expect_error(() => @moon_android.render_template_script(leaked)) {
    KeyMaterialEmbedded => ()
    _ => fail("expected KeyMaterialEmbedded")
  }
  // 篡改计划：Aapt2Compile 需要 build_tools，缺失即 MissingTool。
  let no_tools : @moon_android.BuildConfig = {
    ..template_config(),
    toolchain: { ..locked_toolchain(), build_tools: "", },
  }
  let tampered : @moon_android.GeneratedTree = {
    ..tree,
    build_plan: raw_plan([@moon_android.BuildStep::Aapt2Compile], no_tools),
  }
  match
    @test.expect_error(() => @moon_android.render_template_script(tampered)) {
    MissingTool(tool) => @test.assert_eq(tool, "aapt2")
    _ => fail("expected MissingTool(aapt2)")
  }
}
