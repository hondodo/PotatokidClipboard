# pscreen_control（已废弃）

本项目的遥控端能力已并入 `pscreen_home`：

- 遥控面板 / 会话列表 / 扫码 → `pscreen_home/lib/features/remote_control/`
- 协议构造器 → `packages/pscreen_screen/lib/features/msg/protocol/envelope_builder.dart`
- 目标电视列表资产 → `pscreen_home/assets/tvs.json`
- 相关测试 → `pscreen_home/test/features/remote_control/`

本目录**不再维护、不再单独发布**，仅保留作为迁移参考与回退路径。
