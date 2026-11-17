// 配置值化校验（W4）黑盒测试：SDK 范围矩阵、entry_url 矩阵与防火墙。

///|
test "W4：check_sdk_range 边界矩阵（−1/0/1/23/24/100/101/min>target）" {
  // 合法边界：1 与 100 均在宽松健全上界内。
  for pair in [(1, 1), (1, 100), (23, 24), (24, 34), (100, 100)] {
    let config : @moon_android.BuildConfig = {
      ..demo_config(),
      min_sdk: pair.0,
      target_sdk: pair.1,
    }
    let report = @moon_android.check_sdk_range(config)
    assert_true(report.min_sdk_valid, msg="sdk boundary")
    assert_true(report.target_sdk_valid, msg="sdk boundary")
    assert_true(report.order_valid, msg="sdk boundary")
    @test.assert_eq(report.detail, "ok")
  }
  // 越界与次序违规：逐字段值化，不 raise。
  let cases : Array[(Int32, Int32, Bool, Bool, Bool)] = [
    (-1, 34, false, true, true),
    (0, 34, false, true, true),
    (24, 101, true, false, true),
    (24, -5, true, false, false),
    (34, 24, true, true, false),
    (101, 101, false, false, true),
  ]
  for c in cases {
    let config : @moon_android.BuildConfig = {
      ..demo_config(),
      min_sdk: c.0,
      target_sdk: c.1,
    }
    let report = @moon_android.check_sdk_range(config)
    @test.assert_eq(report.min_sdk_valid, c.2)
    @test.assert_eq(report.target_sdk_valid, c.3)
    @test.assert_eq(report.order_valid, c.4)
    assert_true(report.detail != "ok")
  }
  // 确定性：双次调用逐字一致。
  let config : @moon_android.BuildConfig = {
    ..demo_config(),
    min_sdk: 34,
    target_sdk: 24,
  }
  @test.assert_eq(
    @moon_android.check_sdk_range(config).detail,
    @moon_android.check_sdk_range(config).detail,
  )
}

///|
test "W4：check_entry_url 矩阵（WebView 缺/坏 scheme/http/https/file/其他壳）" {
  // WebView 壳：required=true。
  let webview : @moon_android.BuildConfig = {
    ..demo_config(),
    activity: @moon_android.ActivityKind::WebView,
  }
  let missing = @moon_android.check_entry_url({ ..webview, entry_url: None, })
  assert_true(missing.required)
  assert_true(!missing.present)
  assert_true(!missing.scheme_ok)
  assert_true(missing.detail.contains("缺少 entry_url"))
  for
    url in [
      "https://example.com/index.html", "http://example.com", "file:///android_asset/index.html",
      "HTTPS://EXAMPLE.COM", "File:///sdcard/x.html",
    ] {
    let report = @moon_android.check_entry_url({
      ..webview,
      entry_url: Some(url),
    })
    assert_true(report.required, msg=url)
    assert_true(report.present, msg=url)
    assert_true(report.scheme_ok, msg=url)
    @test.assert_eq(report.detail, "ok")
  }
  for
    bad in [
      "ftp://example.com", "javascript:alert(1)", "example.com", "", "https:/x",
    ] {
    let report = @moon_android.check_entry_url({
      ..webview,
      entry_url: Some(bad),
    })
    assert_true(report.required, msg=bad)
    assert_true(report.present, msg=bad)
    assert_true(!report.scheme_ok, msg=bad)
    assert_true(report.detail.contains("scheme 非法"))
  }
  // 其他壳：required=false，报告恒真（present/scheme_ok 如实填写）。
  for
    kind in [
      @moon_android.ActivityKind::NativeOnly,
      @moon_android.ActivityKind::GlesSurface,
    ] {
    let other : @moon_android.BuildConfig = { ..demo_config(), activity: kind, }
    let none_report = @moon_android.check_entry_url({
      ..other,
      entry_url: None,
    })
    assert_true(!none_report.required)
    assert_true(!none_report.present)
    assert_true(none_report.scheme_ok)
    let some_report = @moon_android.check_entry_url({
      ..other,
      entry_url: Some("https://example.com"),
    })
    assert_true(!some_report.required)
    assert_true(some_report.present)
    assert_true(some_report.scheme_ok)
  }
}

///|
test "W4：防火墙——旧 plan_build 对同语料放行行为不变" {
  // 值化校验不改变 plan_build 既有放行语义（负值/越界/缺 URL 仍放行）。
  let odd : @moon_android.BuildConfig = {
    ..demo_config(),
    min_sdk: -5,
    target_sdk: 200,
    signing_schemes: [
      @moon_android.SigningScheme::V1,
      @moon_android.SigningScheme::V2,
    ],
    activity: @moon_android.ActivityKind::WebView,
    entry_url: None,
  }
  let report = @moon_android.check_sdk_range(odd)
  assert_true(!report.min_sdk_valid)
  assert_true(!report.target_sdk_valid)
  let plan = @moon_android.plan_build(odd, [])
  @test.assert_eq(plan.steps.length(), 10)
  assert_true(!@moon_android.check_entry_url(odd).scheme_ok)
}
