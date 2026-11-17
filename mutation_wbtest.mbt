// L1 变异语料（W9）：固定种子 LCG，4 语料 × 300 = 1200 变异体（≥1000）。
// 断言口径（测试系统设计 §4）：自由字符串变异后「要么报声明的 14 变体之一，
// 要么成功（输出可能不同）」，不得断言全部必错（防假绿）；规格字段
// （sha256 / 版本首字符）单字符破坏必被对应规格校验拒绝。全程无 panic/挂起。

///|
/// 固定种子线性同余生成器（UInt32 自然回绕，确定性可复现）。
struct Lcg {
  mut seed : UInt32
}

///|
fn Lcg::next(self : Lcg) -> UInt32 {
  self.seed = self.seed * 1664525U + 1013904223U
  self.seed
}

///|
fn Lcg::below(self : Lcg, bound : Int32) -> Int32 {
  (self.next() & 0x7FFFFFFFU).reinterpret_as_int() % bound
}

///|
/// 第二个合法 sha256 样例（白盒侧本地定义，与黑盒夹具同值）。
fn wb_second_sha256() -> String {
  "fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210"
}

///|
/// 内部助手：字符数组 → 字符串。
fn chars_to_string(chars : Array[Char]) -> String {
  let mut out = ""
  for c in chars {
    out = out + c.to_string()
  }
  out
}

///|
/// 内部助手：单点变异（替换 / 删除 / 插入，由 rng 决定）。
fn mutate_string(s : String, rng : Lcg, alphabet : String) -> String {
  let chars = s.to_array()
  let alpha = alphabet.to_array()
  let c = alpha[rng.below(alpha.length())]
  let op = rng.below(3)
  if chars.length() == 0 {
    return c.to_string()
  }
  let pos = rng.below(chars.length())
  match op {
    0 => {
      chars[pos] = c
      chars_to_string(chars)
    }
    1 => {
      let out : Array[Char] = []
      for i in 0..<chars.length() {
        if i != pos {
          out.push(chars[i])
        }
      }
      chars_to_string(out)
    }
    _ => {
      let out : Array[Char] = []
      for i in 0..<chars.length() {
        if i == pos {
          out.push(c)
        }
        out.push(chars[i])
      }
      chars_to_string(out)
    }
  }
}

///|
/// 内部助手：错误必须是声明的 14 变体之一（簿记门禁的测试侧承载）。
fn assert_declared_error(e : Error) -> Unit raise Error {
  match e {
    InvalidPackage(_)
    | UnsupportedAbi(_)
    | MissingTool(_)
    | ToolchainNotLocked(_)
    | InvalidStepOrder(_, _)
    | KeyMaterialEmbedded
    | SigningSchemeConflict(_)
    | ArtifactMismatch(_)
    | MissingGate(_)
    | MissingAbi(_)
    | InvalidNativeLib(_)
    | InvalidAsset(_)
    | InvalidTemplate(_)
    | InvalidJdkProbe(_) => ()
    _ => fail("undeclared error type escaped")
  }
}

///|
test "W9 变异语料：包名 300 变异体（仅声明错误或放行，无 panic）" {
  let rng : Lcg = { seed: 20261116U, }
  let base = demo_config()
  let mut ok = 0
  let mut err = 0
  for _ in 0..<300 {
    let name = mutate_string("com.example.app", rng, "abz09.-_! /\\")
    let config : BuildConfig = { ..base, package_id: { name, }, }
    let plan = plan_build(config, []) catch {
      e => {
        assert_declared_error(e)
        err = err + 1
        continue
      }
    }
    ok = ok + 1
    // 放行时渲染仍须确定（不 panic）。
    let _text = render_script(plan)
  }
  @test.assert_eq(ok + err, 300)
  assert_true(err > 0) // 语料必须真的触发过拒绝（防假绿）。
}

///|
test "W9 变异语料：soname 300 变异体（仅声明错误或放行，无 panic）" {
  let rng : Lcg = { seed: 880301U, }
  let mut ok = 0
  let mut err = 0
  for _ in 0..<300 {
    let soname = mutate_string("libapp.so", rng, "abz09.-_!/\\ ")
    let libs = plan_native_libs(dual_abi_set(), soname) catch {
      e => {
        assert_declared_error(e)
        err = err + 1
        continue
      }
    }
    ok = ok + 1
    @test.assert_eq(libs.length(), 2)
  }
  @test.assert_eq(ok + err, 300)
  assert_true(err > 0)
}

///|
test "W9 变异语料：sha256 单字符破坏 300 例必被规格校验拒绝" {
  let libs = plan_native_libs(dual_abi_set(), "libapp.so")
  let base_hash = good_sha256()
  let chars = base_hash.to_array()
  let mut rejected = 0
  for i in 0..<300 {
    let pos = i % chars.length()
    let broken : Array[Char] = []
    for j in 0..<chars.length() {
      broken.push(if j == pos { '!' } else { chars[j] })
    }
    let corrupted = chars_to_string(broken)
    let attached = attach_native_hashes(libs, [
      { abi: Arm64V8a, sha256: corrupted, },
      { abi: ArmeabiV7a, sha256: wb_second_sha256(), },
    ]) catch {
      InvalidNativeLib(_) => {
        rejected = rejected + 1
        continue
      }
      e => {
        assert_declared_error(e)
        fail("sha256 corruption must raise InvalidNativeLib")
      }
    }
    let _ = attached
    fail("sha256 corruption must not pass")
  }
  @test.assert_eq(rejected, 300)
}

///|
test "W9 变异语料：版本号首字符破坏 300 例必 fail-closed（jdk_major → None）" {
  let rng : Lcg = { seed: 424242U, }
  let mut none_count = 0
  for _ in 0..<300 {
    let tail = mutate_string("17.0.9", rng, "0123456789.-ea")
    let version = "x" + tail
    match jdk_major(version) {
      None => none_count = none_count + 1
      Some(_) => fail("non-digit leading char must be fail-closed")
    }
  }
  @test.assert_eq(none_count, 300)
}

///|
test "W9 变异语料：固定种子可复现（双跑计数逐字一致）" {
  fn run_corpus() -> (Int32, Int32) raise Error {
    let rng : Lcg = { seed: 20261116U, }
    let base = demo_config()
    let mut ok = 0
    let mut err = 0
    for _ in 0..<300 {
      let name = mutate_string("com.example.app", rng, "abz09.-_! /\\")
      let config : BuildConfig = { ..base, package_id: { name, }, }
      let _plan = plan_build(config, []) catch {
        e => {
          assert_declared_error(e)
          err = err + 1
          continue
        }
      }
      ok = ok + 1
    }
    (ok, err)
  }
  let first = run_corpus()
  let second = run_corpus()
  @test.assert_eq(first.0, second.0)
  @test.assert_eq(first.1, second.1)
}
