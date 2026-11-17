///|
/// 配置值化校验（W4，纯加法）：校验结论以**报告值**表达，不新增错误
/// 变体、不改 `plan_build` 既有放行行为（防火墙：旧 API 语义永不改变）。
/// 调用方（组合根 / CLI）自行决定是否据报告拒绝。两函数零 raise、纯计算。

///|
/// SDK 范围校验报告（纯值）。
pub(all) struct SdkRangeReport {
  min_sdk_valid : Bool
  target_sdk_valid : Bool
  order_valid : Bool
  detail : String
}

///|
/// 校验配置的 SDK 范围（零 raise，纯计算）。
///
/// 口径：`min_sdk` / `target_sdk` ∈ 1..=100 且 `min_sdk ≤ target_sdk`。
/// 100 为**宽松健全上界**（非官方最大 API 级；官方最新级别为易变事实
/// [需联网核实]），只用于排除荒谬值；真实约束以组合时的 AGP/Play 政策为准。
/// `detail` 为确定性问题清单（分号分隔），全部通过时为 `"ok"`。
pub fn check_sdk_range(config : BuildConfig) -> SdkRangeReport {
  let min_ok = config.min_sdk >= 1 && config.min_sdk <= 100
  let target_ok = config.target_sdk >= 1 && config.target_sdk <= 100
  let order_ok = config.min_sdk <= config.target_sdk
  let issues : Array[String] = []
  if !min_ok {
    issues.push("min_sdk 越界（1..=100）：\{config.min_sdk}")
  }
  if !target_ok {
    issues.push("target_sdk 越界（1..=100）：\{config.target_sdk}")
  }
  if !order_ok {
    issues.push(
      "min_sdk > target_sdk：\{config.min_sdk} > \{config.target_sdk}",
    )
  }
  let mut detail = ""
  for issue in issues {
    if detail != "" {
      detail = detail + "; "
    }
    detail = detail + issue
  }
  if detail == "" {
    detail = "ok"
  }
  {
    min_sdk_valid: min_ok,
    target_sdk_valid: target_ok,
    order_valid: order_ok,
    detail,
  }
}

///|
/// entry_url 校验报告（纯值）。
pub(all) struct EntryUrlReport {
  required : Bool
  present : Bool
  scheme_ok : Bool
  detail : String
}

///|
/// 内部助手：URL scheme 是否 ∈ {http, https, file}（大小写不敏感）。
fn entry_scheme_ok(url : String) -> Bool {
  let lower = url.to_lower()
  lower.has_prefix("http://") ||
  lower.has_prefix("https://") ||
  lower.has_prefix("file://")
}

///|
/// 校验配置的 entry_url（零 raise，纯计算）。
///
/// 口径：`WebView` 壳 `required = true`，要求 `Some` 且 scheme ∈
/// {http, https, file}（大小写不敏感）；其余壳（`GlesSurface` /
/// `NativeOnly`）`required = false`，报告恒真（`present` / `scheme_ok`
/// 仍按实际值如实填写，供调用方参考）。
pub fn check_entry_url(config : BuildConfig) -> EntryUrlReport {
  let required = config.activity is WebView
  match config.entry_url {
    Some(url) => {
      let scheme_ok = entry_scheme_ok(url)
      let detail = if !required {
        "ok（非 WebView 壳，entry_url 可选）"
      } else if scheme_ok {
        "ok"
      } else {
        "scheme 非法（需 http/https/file）：" + url
      }
      { required, present: true, scheme_ok, detail, }
    }
    None => {
      let detail = if required {
        "WebView 壳缺少 entry_url"
      } else {
        "ok（非 WebView 壳，entry_url 可选）"
      }
      { required, present: false, scheme_ok: !required, detail, }
    }
  }
}
