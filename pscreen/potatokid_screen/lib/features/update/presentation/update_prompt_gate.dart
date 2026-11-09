import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pscreen_screen/core/update/app_update_controller.dart';

/// 可用更新弹窗门控：挂载在 [MaterialApp.builder] 上。
///
/// 首次检测到有可用更新（且非强更拦截）时弹一次「发现新版本」对话框；
/// 「立即更新」触发下载/安装（已就绪则直接拉起系统安装器），「稍后」仅关闭。
/// [MaterialApp.router] 组件被重建也只提示一次。
///
/// 电视端用：AlertDialog 的按钮走焦点系统，遥控方向键 + OK 即可操作，
/// 主按钮 autofocus 默认选中。
class UpdatePromptGate extends StatefulWidget {
  const UpdatePromptGate({super.key, required this.child, this.navigatorKey});

  final Widget child;

  /// 根 Navigator 的 key。
  ///
  /// 本组件挂在 [MaterialApp.builder] 上，它的 context 在 Navigator **之上**，
  /// 直接 `showDialog(context: context)` 会抛
  /// 「Navigator operation requested with a context that does not include a Navigator」，
  /// 因此弹窗必须借用根 Navigator 的 overlay context。
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  State<UpdatePromptGate> createState() => _UpdatePromptGateState();
}

class _UpdatePromptGateState extends State<UpdatePromptGate> {
  /// 进程级一次性标志：同一次启动只提示一次。
  static bool _prompted = false;
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    AppUpdateController.instance.addListener(_maybeShow);
    // 初始化时状态可能已就绪（check 早于本组件挂载），主动补一次检查。
    _maybeShow();
  }

  @override
  void dispose() {
    AppUpdateController.instance.removeListener(_maybeShow);
    super.dispose();
  }

  void _maybeShow() {
    if (_prompted || _showing || !mounted) return;
    final AppUpdateState state = AppUpdateController.instance.state;
    if (state.forceBlocked) return; // 强更整页接管，不弹普通提示。
    if (state.result?.hasUpdate != true) return;
    if (state.phase == AppUpdatePhase.installing) return;
    debugPrint(
      '[UpdatePrompt] 触发弹窗 hasUpdate=${state.result?.hasUpdate} '
      'phase=${state.phase} nav=${widget.navigatorKey?.currentState != null}',
    );
    _showing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _showing = false;
        return;
      }
      unawaited(_showPrompt());
    });
  }

  Future<void> _showPrompt() async {
    final AppUpdateController controller = AppUpdateController.instance;
    final AppUpdateState state = controller.state;
    final latest = state.result?.latest;
    if (latest == null) {
      _showing = false;
      return;
    }

    // 本组件 context 在 Navigator 之上，必须借用根 Navigator 的 overlay context；
    // 取不到（导航尚未挂载）就不置 [_prompted]，留给后续状态变化重试。
    final BuildContext? navContext =
        widget.navigatorKey?.currentState?.overlay?.context;
    debugPrint('[UpdatePrompt] showPrompt navContext=${navContext != null}');
    if (navContext == null || !mounted) {
      _showing = false;
      return;
    }
    _prompted = true; // 先置位：本次启动后续状态变化不再触发。

    final bool ready = state.phase == AppUpdatePhase.ready;
    final int? bytes = state.result?.download?.size;
    final String sizeText = bytes != null && bytes > 0
        ? '（约 ${(bytes / 1024 / 1024).toStringAsFixed(1)}MB）'
        : '';
    final String title = ready ? '新版本已就绪' : '发现新版本';
    final String body = ready
        ? '新版本 v${latest.version}+${latest.build} 已下载完成，是否立即安装？'
        : '检测到新版本 v${latest.version}+${latest.build}$sizeText，是否立即更新？';

    if (!mounted) {
      _showing = false;
      return;
    }
    await showDialog<void>(
      context: navContext,
      barrierDismissible: false, // 遥控无触摸：需明确选择（back 键等同「稍后」）。
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('稍后'),
            ),
            FilledButton(
              autofocus: true, // 打开即聚焦主按钮，遥控 OK 直接确认。
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                if (ready) {
                  await controller.install();
                  return;
                }
                // 「立即更新」= 下载完直接进安装，避免用户以为点完就该升级、
                // 却只看到下载进度（此前只下载不安装）。
                await controller.ensureDownloadedNow();
                if (controller.state.phase == AppUpdatePhase.ready) {
                  final bool started = await controller.install();
                  if (!started && navContext.mounted) {
                    ScaffoldMessenger.maybeOf(navContext)?.showSnackBar(
                      const SnackBar(
                        content: Text('无法拉起系统安装器，请检查「安装未知应用」权限'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                }
              },
              child: Text(ready ? '立即安装' : '立即更新'),
            ),
          ],
        );
      },
    );
    _showing = false;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
