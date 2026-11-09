// 通用模板白盒测试：路径/依赖/应用名规则、XML 转义与脚本分隔符助手。

///|
test "relative_path_ok / valid_module_dep / valid_app_name 规则矩阵" {
  for good in ["a", "a/b", "a/b.txt", "res/values/strings.xml", "a-b_c.d"] {
    assert_true(relative_path_ok(good), msg=good)
  }
  for
    bad in [
      "", "/abs", "../a", "a/../b", "a//b", "a/", "a\\b", "C:/a", "a b", "a:b",
    ] {
    assert_true(!relative_path_ok(bad), msg=bad)
  }
  for good in ["moon_android", "hnlyxiaobing/moon_abi", "bobzhang/zip@0.1.2"] {
    assert_true(valid_module_dep(good), msg=good)
  }
  for bad in ["", "/abs", "a//b", "a/../b", "a b", "a:b"] {
    assert_true(!valid_module_dep(bad), msg=bad)
  }
  assert_true(valid_app_name("Demo App"))
  assert_true(valid_app_name("红米电视 Demo"))
  assert_true(!valid_app_name(""))
  assert_true(!valid_app_name("   "))
  assert_true(!valid_app_name("a\nb"))
}

///|
test "soname_stem 提取 `lib<stem>.so` 的 stem" {
  assert_true(soname_stem("libapp.so").length() > 0)
  @test.assert_eq(soname_stem("libapp.so"), "app")
  @test.assert_eq(soname_stem("libapp.v2.so"), "app.v2")
}

///|
test "xml_escape / parent_dir / contains_line / heredoc_marker" {
  @test.assert_eq(
    xml_escape("A & B <C> \"D\" 'E'"),
    "A &amp; B &lt;C&gt; &quot;D&quot; &apos;E&apos;",
  )
  @test.assert_eq(xml_escape("plain"), "plain")
  @test.assert_eq(parent_dir("a/b/c.txt"), "a/b")
  @test.assert_eq(parent_dir("a.txt"), "")
  @test.assert_eq(parent_dir("/abs"), "")
  assert_true(contains_line("x\nMOON_ANDROID_EOF_0\ny", "MOON_ANDROID_EOF_0"))
  assert_true(!contains_line("xMOON_ANDROID_EOF_0", "MOON_ANDROID_EOF_0"))
  assert_true(ends_with_newline("a\n"))
  assert_true(!ends_with_newline("a"))
  @test.assert_eq(heredoc_marker(7), "MOON_ANDROID_EOF_7")
}
