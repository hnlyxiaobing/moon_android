///|
/// 双 ABI `.so` 管理：ABI 目录名、native 库清单、SHA-256 登记与校验。
///
/// 边界：本文件只做**纯值计划与校验**——不编译 `.so`、不读文件、不算哈希、
/// 不读写 `jniLibs/`。`.so` 本体与哈希由组合根在本机产生后填入；真实
/// `.so` 禁止入库（只允许本地链接 + SHA-256 + PROVENANCE 登记）。
/// 所有失败路径统一 `raise MoonAndroidError`；畸形输入不 panic。

///|
/// ABI 的 Android 目录名（即 `lib/<dir>` 中的 `<dir>`）：
/// `Arm64V8a -> "arm64-v8a"`、`ArmeabiV7a -> "armeabi-v7a"`、
/// `X86 -> "x86"`、`X86_64 -> "x86_64"`。
pub fn abi_dir_name(abi : Abi) -> String {
  abi_name(abi)
}

///|
/// R4 双 ABI 基线集：`arm64-v8a`（64 位主 ABI）+ `armeabi-v7a`（32 位兼容）。
/// 返回新数组，调用方可自由修改。
pub fn dual_abi_set() -> Array[Abi] {
  [Arm64V8a, ArmeabiV7a]
}

///|
/// 一个本地 native 库（`.so`）条目。
///
/// - `dir` 必须等于 `abi_dir_name(abi)`（清单自洽，防手写漂移）；
/// - `sha256` 为 `None` 表示**尚未构建 / 尚未登记**，是显式状态而非通过；
///   需要生成可归档清单时必须先用 `attach_native_hashes` 登记。
pub(all) struct NativeLib {
  abi : Abi
  dir : String
  soname : String
  sha256 : String?
}

///|
/// 一个 ABI 的 `.so` SHA-256 登记项（组合根在本机构建后计算并传入）。
pub(all) struct LibHash {
  abi : Abi
  sha256 : String
}

///|
/// 内部助手：`lib<stem>.so` 形式的库名合法性。
/// 要求：前缀 `lib`、后缀 `.so`、stem 非空、字符集 `[A-Za-z0-9_.-]`、
/// 不含 `..`。路径分隔符 / 盘符 / 反斜杠一律拒绝（防目录穿越）。
fn valid_soname(name : String) -> Bool {
  let chars = name.to_array()
  let n = chars.length()
  if n <= 6 {
    return false
  }
  if chars[0] != 'l' || chars[1] != 'i' || chars[2] != 'b' {
    return false
  }
  if chars[n - 3] != '.' || chars[n - 2] != 's' || chars[n - 1] != 'o' {
    return false
  }
  for i in 3..<(n - 3) {
    let c = chars[i]
    let ok = (c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') ||
      (c >= '0' && c <= '9') ||
      c == '_' ||
      c == '.' ||
      c == '-'
    if !ok {
      return false
    }
  }
  // 任意连续点号一律拒绝（覆盖 `lib..so` / `liba..b.so` 一类穿越写法）。
  for i in 0..<(n - 1) {
    if chars[i] == '.' && chars[i + 1] == '.' {
      return false
    }
  }
  true
}

///|
/// 内部助手：清单中是否已含某个 ABI（按目录名比较，避免名义枚举比较歧义）。
fn has_abi(libs : Array[NativeLib], abi : Abi) -> Bool {
  let want = abi_dir_name(abi)
  for lib in libs {
    if lib.dir == want {
      return true
    }
  }
  false
}

///|
/// 内部助手：结构性校验清单条目（不要求哈希已登记）。
/// 空清单 → `UnsupportedAbi("none")`；重复 ABI → `UnsupportedAbi(dir)`；
/// 目录与 ABI 不一致 / 库名非法 / 哈希格式非法 → `InvalidNativeLib`。
fn validate_native_lib_entries(
  libs : Array[NativeLib],
) -> Unit raise MoonAndroidError {
  if libs.length() == 0 {
    raise UnsupportedAbi("none")
  }
  for i in 0..<libs.length() {
    for j in (i + 1)..<libs.length() {
      if libs[i].dir == libs[j].dir {
        raise UnsupportedAbi(libs[i].dir)
      }
    }
  }
  for lib in libs {
    if lib.dir != abi_dir_name(lib.abi) {
      raise InvalidNativeLib("目录与 ABI 不一致：" + lib.dir)
    }
    if !valid_soname(lib.soname) {
      raise InvalidNativeLib("soname 非法：" + lib.soname)
    }
    match lib.sha256 {
      Some(hash) =>
        if !is_sha256_hex(hash) {
          raise InvalidNativeLib("sha256 非法：" + lib.dir)
        }
      None => ()
    }
  }
}

///|
/// 生成 native 库目录清单（按输入 ABI 顺序，不重排；`sha256 = None`）。
///
/// - 参数：`abis` 为生效 ABI 集；`soname` 必须是 `lib<stem>.so`。
/// - 错误：ABI 集为空 → `UnsupportedAbi("none")`；重复 ABI →
///   `UnsupportedAbi(dir)`；库名非法 → `InvalidNativeLib(soname)`。
/// - 用途：预构建阶段确定 `lib/<dir>/<soname>` 落点（双 ABI 基线见
///   `dual_abi_set`）。
pub fn plan_native_libs(
  abis : Array[Abi],
  soname : String,
) -> Array[NativeLib] raise MoonAndroidError {
  validate_abis(abis)
  if !valid_soname(soname) {
    raise InvalidNativeLib("soname 非法：" + soname)
  }
  let libs : Array[NativeLib] = []
  for abi in abis {
    libs.push({ abi, dir: abi_dir_name(abi), soname, sha256: None, })
  }
  libs
}

///|
/// 由 Android ABI 目录名反解 `Abi`（大小写敏感，与 Android 命名一致）。
///
/// 非法名（含空串、大小写变体、尾随空格）→ `UnsupportedAbi(name)`。
pub fn parse_abi_dir_name(name : String) -> Abi raise MoonAndroidError {
  if name == "armeabi-v7a" {
    ArmeabiV7a
  } else if name == "arm64-v8a" {
    Arm64V8a
  } else if name == "x86" {
    X86
  } else if name == "x86_64" {
    X86_64
  } else {
    raise UnsupportedAbi(name)
  }
}

///|
/// 给 native 库清单附加 SHA-256（组合根构建后回填）。
///
/// - 每个清单 ABI 必须恰有一条哈希；缺失 → `MissingAbi(dir)`。
/// - 重复哈希项 / 哈希项中的 ABI 不在清单 / 哈希非 64 位十六进制 →
///   `InvalidNativeLib`。
/// - 返回新数组，输入不变（纯函数）。
pub fn attach_native_hashes(
  libs : Array[NativeLib],
  hashes : Array[LibHash],
) -> Array[NativeLib] raise MoonAndroidError {
  validate_native_lib_entries(libs)
  for i in 0..<hashes.length() {
    for j in (i + 1)..<hashes.length() {
      let a = abi_dir_name(hashes[i].abi)
      let b = abi_dir_name(hashes[j].abi)
      if a == b {
        raise InvalidNativeLib("重复哈希项：" + a)
      }
    }
  }
  for entry in hashes {
    let dir = abi_dir_name(entry.abi)
    if !has_abi(libs, entry.abi) {
      raise InvalidNativeLib("哈希项中的 ABI 不在清单：" + dir)
    }
    if !is_sha256_hex(entry.sha256) {
      raise InvalidNativeLib("sha256 非法：" + dir)
    }
  }
  let out : Array[NativeLib] = []
  for lib in libs {
    let mut found : String? = None
    for entry in hashes {
      if abi_dir_name(entry.abi) == lib.dir {
        found = Some(entry.sha256)
      }
    }
    match found {
      Some(hash) =>
        out.push({
          abi: lib.abi,
          dir: lib.dir,
          soname: lib.soname,
          sha256: Some(hash),
        })
      None => raise MissingAbi(lib.dir)
    }
  }
  out
}

///|
/// 校验 native 库清单完整性：结构（目录/库名/重复）+ 哈希已登记 +
/// `required` 中的 ABI 全部在场。
///
/// - 结构问题：`UnsupportedAbi("none")` / `UnsupportedAbi(dir)` /
///   `InvalidNativeLib`。
/// - 哈希未登记：`InvalidNativeLib("SHA-256 未登记：<dir>")`（fail-closed：
///   未登记不等于通过）。
/// - 缺失 ABI：`MissingAbi(dir)`（双 ABI 用 `dual_abi_set()` 作 `required`）。
pub fn validate_native_manifest(
  libs : Array[NativeLib],
  required : Array[Abi],
) -> Unit raise MoonAndroidError {
  validate_native_lib_entries(libs)
  for lib in libs {
    match lib.sha256 {
      Some(_) => ()
      None => raise InvalidNativeLib("SHA-256 未登记：" + lib.dir)
    }
  }
  for abi in required {
    if !has_abi(libs, abi) {
      raise MissingAbi(abi_dir_name(abi))
    }
  }
}

///|
/// 渲染确定性的 native 库清单文本（一行一 ABI）：
/// `lib/<dir>/<soname>  sha256=<hex>`。
///
/// 哈希未登记或条目非法时拒绝渲染（`InvalidNativeLib`），保证产出的清单
/// 永远是已登记状态，可直接归档为 PROVENANCE 证据。
pub fn render_native_manifest(
  libs : Array[NativeLib],
) -> String raise MoonAndroidError {
  validate_native_manifest(libs, [])
  let mut text = "# moon_android native lib manifest (deterministic; sha256 by composition root)\n"
  text = text + "# entries: \{libs.length()}\n"
  for lib in libs {
    let hash = match lib.sha256 {
      Some(h) => h
      None => ""
    }
    text = text +
      "lib/" +
      lib.dir +
      "/" +
      lib.soname +
      "  sha256=" +
      hash +
      "\n"
  }
  text
}
