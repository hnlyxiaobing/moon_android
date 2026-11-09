// Windows JDK 探测白盒测试：版本解析与路径归一化。

///|
test "jdk_major 版本解析矩阵（含 1.x 旧式与 fail-closed）" {
  assert_true(jdk_major("17") is Some(17))
  assert_true(jdk_major("17.0.9") is Some(17))
  assert_true(jdk_major("21-ea") is Some(21))
  assert_true(jdk_major("1.8.0_202") is Some(8))
  assert_true(jdk_major("1.17.0") is Some(17))
  assert_true(jdk_major(" 17.0.1 ") is Some(17))
  assert_true(jdk_major("") is None)
  assert_true(jdk_major("jdk-17") is None)
  assert_true(jdk_major("v17") is None)
  assert_true(jdk_major(".") is None)
}

///|
test "normalize_jdk_dir 引号/反斜杠/尾斜杠/相对路径矩阵" {
  match normalize_jdk_dir("\"C:\\Program Files\\Java\\jdk-17\\\"") {
    Some(path) => {
      @test.assert_eq(path.display, "C:/Program Files/Java/jdk-17")
      @test.assert_eq(path.key, "c:/program files/java/jdk-17")
    }
    None => fail("expected normalized path")
  }
  match normalize_jdk_dir("c:/java/jdk17//") {
    Some(path) => @test.assert_eq(path.display, "c:/java/jdk17")
    None => fail("expected normalized path")
  }
  // POSIX 绝对路径（Linux CI 场景）。
  match normalize_jdk_dir("/usr/lib/jvm/jdk-17") {
    Some(path) => @test.assert_eq(path.display, "/usr/lib/jvm/jdk-17")
    None => fail("expected normalized posix path")
  }
  for bad in ["", "   ", "relative/jdk", "./jdk", "C:", "/"] {
    assert_true(normalize_jdk_dir(bad) is None, msg=bad)
  }
}
