# 项目术语与部署约定

## 术语对照

| 日常称呼 | 实际指向 |
| --- | --- |
| home端 / 中控端 | `pscreen_home` |
| tv端 | `potatokid_screen`（源码在 `pscreen/potatokid_screen`） |
| 本地服务 / 数据服务 | `pscreen_server/server` |
| 应用服务 | `app_server` |
| 本地部署 | `ssh 100.83.142.107` 这台机，部署目录 `services/tools/` |
| 远程部署 / yuntu部署 | `ssh yuntu` 这台机 |

## 部署规则

- 进程管理统一使用 **pm2**。
- **必须先改源码，再部署到目标机器**。禁止直接修改部署机器里的文件，否则源码与部署代码不同步，会导致功能缺失。

## 环境相关的部署位置（原有记录）

如果当前在windows这台机：
app_server 在ssh yuntu  ；pscreen_server 服务在 ssh 100.83.142.107 (honghao@honghao-MacBookPro12-1:~/services/tools$) 如果需要查看可在这两台机看，但必须保证在源代码里修改再部署，不能直接在部署目录修改导致代码不同步。它们都是pm2
如果当前在ubuntu这台机：
app_server 在ssh yuntu  ；pscreen_server 服务在当前ubuntu这台机 (honghao@honghao-MacBookPro12-1:~/services/tools$) 如果需要查看可在这两台机看，但必须保证在源代码里修改再部署，不能直接在部署目录修改导致代码不同步。它们都是pm2