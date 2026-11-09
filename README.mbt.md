# hnlyxiaobing/moon_android

> 实现完成 · **API 冻结前对账（2026-11-07）**。本包提供构建计划 / 版本锁 / 门禁值类型、`BuildPlanner` trait 与 `plan_build` / `render_script` / `verify_artifact` / `ci_gate_plan` 4 个函数的**真实实现**，**不执行任何外部命令、不签名、不调 adb**。四道门禁 `moon check --deny-warn` / `moon build` / `moon test` / `moon fmt --check`：全绿（39 tests，0 条 `0068`）。**冻结后签名变更即破坏性变更。**

APK 打包链的「计划与配置」层。模板泛化后移，先用一次性脚本验证设备端通路，详见同目录 `README.md`「排序修正」与 `DECISIONS.md` 决策 2。

完整文档见同目录 `README.md`、`DESIGN.md`、`API.md`；设计决策记录见同目录 `DECISIONS.md`。

**当前状态：实现完成，四道门禁全绿，等待集成。**
