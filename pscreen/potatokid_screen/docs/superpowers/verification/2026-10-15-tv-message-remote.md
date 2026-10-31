# TV 消息遥控 验证报告

## 自动化
- flutter analyze: No issues found (22.5s)
- flutter test: 99/99 All tests passed
- flutter build apk --debug: BUILD SUCCESSFUL → `build\app\outputs\flutter-apk\app-debug.apk`（208.3s，仅 nim_core_v2 第三方 Kotlin 警告，无本项目错误）

## 提交序列（feature/remote_msg）
```
48177de fix: reporting account switch edge and dispose ownership
fdc45dd feat: wire msg module receive and reporting
40ae9a8 fix: reporting start race guard and heartbeat tests
caacd6c feat: admin reporting service
f373c32 fix: detail pane d-pad scroll and overlay slide-in animation
4373c30 feat: message overlay ui with global key intercept
26e8c12 test: channel command bounds and null args
b55980c feat: message router and command executor
d9b6737 fix: overlay pending clear and detail-preserve on replace
84b4b76 feat: message overlay controller state machine
06c4c97 feat: channel info and tab state providers
4be287e feat: nim message receive stream and text send
e57bc0f fix: envelope trim-based discrimination
61963d1 feat: message envelope parser
2c83cc0 feat: PlatformChannelService 音量控制 + 设备型号通道
```

## 手动清单状态
| # | 项 | 状态 |
|---|----|------|
| 1 | 管理员手机发纯文本 → TV 弹浮层、焦点抢占、OK 详情、两级返回、1 分钟自动关 | 待真机 |
| 2 | 连发两条 → 第二条直接替换、计时重置 | 待真机 |
| 3 | 发 volume_up 命令 → 系统音量条出现且音量+ | 待真机 |
| 4 | channel 命令 → 切台且 1 秒后 TV 向 1000001 发「切换频道：xxx」 | 待真机 |
| 5 | TV 登录 → 1000001 收到两条登录消息；5 分钟后收到心跳 | 待真机 |
| 6 | 屏保中发文本 → 退出屏保后弹出 | 待真机 |
| 7 | 「远程」行编辑态（已登录）→ 二维码显示 | 待真机 |
| 8 | 未登录 TV → 上报不发、二维码不显示 | 待真机 |

## 已知遗留
- 评审中标记为 Minor 的未修项：无记录（Task1–9 序列中未留存 Minor 评审清单；如有遗漏可在真机验证时补充）
- 上述 8 项均需真机 + 管理员手机端配合，无法自动化（按任务说明不模拟）
