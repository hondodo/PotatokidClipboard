# pscreen_control 发送端 验证报告

## 自动化
- flutter analyze: No issues found (11.5s)
- flutter test: 32/32 All tests passed

## 提交序列（feature/remote_msg, pscreen_control）
```
7795af3 feat: control app scaffold deps di settings
116b035 fix: registrants, defensive AppSettings, guarded NIM init
239e23c feat: nim client login settings and tv directory
f13d778 fix: wire TvDirectory.loadFromAssets and persist token after login success
e9e3ddb feat: envelope builder and send cubit
2439473 fix: send re-entrancy guard and coverage for clearResults incremental emit
c29e746 feat: send page with admin broadcast and family fork
c158d6f fix: banner overflow keyboard scroll and send feedback
41be982 feat: qr scan conversation list and chat page
c5591f9 fix: conversation peer derivation, local source, cubit guards, mark read
74bf53a feat: offline hint selected targets persistence
c6715d8 docs: sender app known limitations and verification report
3a7ebed fix: cubit close guards, persist after final emit, non-preset target chips
51e8f75 fix: family single target role-scoped persistence chat accumulation disconnect detection
```

## 手动清单状态
| # | 项 | 状态 |
|---|----|------|
| 1 | 设置页登录管理员 `1000001` + token → 进入群发 Tab | 待真机 |
| 2 | 群发页勾选多台 + 发纯文本 → TV 端逐台弹浮层；结果「已发 2/2 台」 | 待真机 |
| 3 | 命令面板音量+/静音 → TV 系统音量变化（无浮层） | 待真机 |
| 4 | 频道命令 → TV 切台 | 待真机 |
| 5 | 扫码：TV 打开远程行编辑浮层 → 手机扫码 → 账号自动填入目标 | 待真机 |
| 6 | 会话 Tab → 点开客厅电视 → 发文本 → TV 弹浮层；TV 上报（登录/切台/心跳）出现在聊天流 | 待真机 |
| 7 | 家人账号登录 → 单页「发指令」，无预设列表，手动/扫码单台发送 | 待真机 |
| 8 | 杀掉 App 重启 → 自动登录进入发送页；最近勾选目标还在 | 待真机 |
| 9 | 断网 → 提示「连接断开」 | 待真机 |

## 已知遗留
- 终审 Minor（未修）：`clearResults` 无 UI 调用点；`easy_localization` 死依赖；发送文本在结果未知前即清空输入框；`TvDirectory.loadFromAssets` 异常未防护；AppSettings 初始化失败静默；ConversationListPage 无 keep-alive（切 Tab 状态丢失）；发送中 CommandPanel 未禁用；AppSettings 各 setter 错误处理不对称；`logout`/`onLoginStatus` 等 API 暂无调用点；`.vscode/` 未纳入版本控制
- watchMessages 仅实时流、isOutgoing 恒 false（已入 spec §8）
- 上述 9 项均需真机 + TV 端配合，无法自动化（按任务说明不模拟）
