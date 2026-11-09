# hnlyxiaobing/moon_android

> **R4（2026-11-09）**。本包提供构建计划 / 版本锁 / 门禁值类型、`BuildPlanner` trait、模板生成树、双 ABI `.so` 清单与 JDK 纯评估器；公开函数 ×14（既有 4 + 新增 10）均为**真实实现**，**不执行任何外部命令、不签名、不调 adb、不读写 APK**。五道门禁 `moon check --deny-warn` / `moon build` / `moon test`（**79 tests**）/ `moon fmt --check` / API 快照：全绿（0 条 `0068`）。**既有签名冻结；R4 为加法性新增。**

APK 打包链的「计划与配置」层。R4 已把**已被计划层验证的纯值接口**泛化为模板（`plan_template` / `render_template_script`，映射见 `docs/TEMPLATE.md`）；设备端通路（E3/Q1）仍未实测，模板化不等于通路已验证。执行链风险与本机实测见 `docs/EXECUTION-CHAIN.md`。

完整文档见项目根目录与 `docs/` 目录：`README.md`、`docs/DESIGN.md`、`docs/API.md`；设计决策记录见 `docs/DECISIONS.md`。

**当前状态：R4 实现完成，五道门禁本机等价实跑全绿；执行链与设备启动 `[仍需实测]`，等待集成。**
