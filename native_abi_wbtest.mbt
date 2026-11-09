// 双 ABI `.so` 管理的白盒测试：库名规则。

///|
test "valid_soname 库名规则" {
  for good in ["libapp.so", "libApp_2.so", "liba-b.c.so", "libcore.so"] {
    assert_true(valid_soname(good), msg=good)
  }
  for
    bad in [
      "", "app.so", "lib.so", "libapp", "libapp.dll", "liba/b.so", "liba\\b.so",
      "lib..so", "lib app.so", "libapp.so ",
    ] {
    assert_true(!valid_soname(bad), msg=bad)
  }
}
