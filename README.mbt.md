# hnlyxiaobing/moon_android

> Round-1 · 架构与声明可评审（2026-11-06）。本包只有构建计划/版本锁/门禁值类型、`BuildPlanner` trait 与 `declare` 函数签名，**不执行任何外部命令、不签名、不调 adb**。`moon check`：0 error，4 × `[0068]`（预期）。

APK 打包链的「计划与配置」层。模板泛化按 ADR-0005 后移到 R4，先用 MVL-D 一次性脚本验证通路，详见同目录 `README.md`「排序修正」。

完整文档见同目录 `README.md`、`DESIGN.md`、`API.md`；总体架构与决策见 `../docs/architecture.md`、`../docs/adr/`。

**当前状态：等待评审，不进入实现。**
