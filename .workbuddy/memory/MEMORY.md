# 项目长期记忆（potatokid_clipboard）

完整约定见项目根目录 `rules.md`，每次涉及部署前应先确认这些规则。

## 术语对照（用户口径，勿自行替换）

- home端 / 中控端 = `pscreen_home`
- tv端 = `potatokid_screen`（源码路径 `pscreen/potatokid_screen`）
- 本地服务 / 数据服务 = `pscreen_server/server`
- 应用服务 = `app_server`
- 本地部署 = `ssh 100.83.142.107`，部署在 `services/tools/`
- 远程部署 / yuntu部署 = `ssh yuntu`

## 部署铁律

- 所有服务用 **pm2** 管理进程。
- **必须先改源码，再部署到目标机器；绝不能直接修改部署机器里的文件**，否则源码与线上不同步、导致功能缺失或后续部署把改动覆盖掉。
- 查看线上代码可以 ssh 到目标机，但只用于排查，不作为修改入口。
- 环境差异：Windows 开发机上 `app_server` 在 yuntu、`pscreen_server` 在 100.83.142.107；Ubuntu 开发机上 `pscreen_server` 就在本机。
