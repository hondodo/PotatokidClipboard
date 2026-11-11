import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:potatokid_screen/shared/widgets/kid_chrome.dart';
import 'package:pscreen_screen/core/update/app_update_controller.dart';

/// 可用更新弹窗门控：挂载在 [MaterialApp.builder] 上。
///
/// 新版本**下载完成**（[AppUpdatePhase.ready]）后弹一次「新版本已就绪」对话框。
///
/// 检测到更新时不再弹窗打扰：后台静默下载，进度由直播页右上角提示与胶囊页展示；
/// 「立即安装」拉起系统安装器，「稍后」仅关闭，同一次启动只提示一次。
///
/// 电视端用：弹窗按钮走焦点系统，遥控方向键 + OK 即可操作，主按钮 autofocus。
/// 儿童模式只换卡片外观与文案（[KidSurface] / 暖黄按钮 / `*_kid` 文案），
/// 文案一律用「按 OK 键 / 按返回键」的遥控口径，不出现「点这里」等触屏说法。
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
    if (_showing || !mounted) return;
    final AppUpdateState state = AppUpdateController.instance.state;
    if (state.forceBlocked) return; // 强更整页接管，不弹普通提示。
    if (state.result?.hasUpdate != true) return;
    // 只在下载完成后提示：检测到更新时保持静默，避免两次弹窗打扰。
    if (state.phase != AppUpdatePhase.ready) return;
    if (_prompted) return;
    debugPrint(
      '[UpdatePrompt] 触发弹窗 hasUpdate=${state.result?.hasUpdate} phase=${state.phase} '
      'nav=${widget.navigatorKey?.currentState != null}',
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
    if (latest == null || state.phase != AppUpdatePhase.ready) {
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
    _prompted = true; // 本次启动只提示一次。

    final bool kid = kidModeOn;
    final String title = kid
        ? 'kid_update_title_ready'.tr()
        : '新版本已就绪';
    final String body = kid
        ? 'kid_update_body_ready'.tr()
        : '新版本 v${latest.version}+${latest.build} 已下载完成，是否立即安装？';
    final String laterLabel = kid ? 'kid_update_later'.tr() : '稍后';
    final String confirmLabel = kid ? 'kid_update_install'.tr() : '立即安装';

    Future<void> confirm(BuildContext dialogCtx) async {
      Navigator.of(dialogCtx).pop(true);
      final bool started = await controller.install();
      if (!started && navContext.mounted) {
        ScaffoldMessenger.maybeOf(navContext)?.showSnackBar(
          kid
              ? kidSnackBar('kid_update_install_failed'.tr())
              : const SnackBar(
                  content: Text('无法拉起系统安装器，请检查「安装未知应用」权限'),
                  behavior: SnackBarBehavior.floating,
                ),
        );
      }
    }

    if (!mounted) {
      _showing = false;
      return;
    }
    await showDialog<bool>(
      context: navContext,
      barrierDismissible: false, // 遥控无触摸：需明确选择（back 键等同「稍后」）。
      builder: (BuildContext dialogContext) {
        if (!kid) {
          return AlertDialog(
            title: Text(title),
            content: Text(body),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(laterLabel),
              ),
              FilledButton(
                autofocus: true,
                onPressed: () => confirm(dialogContext),
                child: Text(confirmLabel),
              ),
            ],
          );
        }
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.all(20),
          child: KidSurface(
            dialog: true,
            width: 620,
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Icon(
                      Icons.auto_awesome_rounded,
                      color: KidPalette.softBlue,
                      size: 28,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  body,
                  style: const TextStyle(color: Colors.white70, fontSize: 19),
                ),
                const SizedBox(height: 10),
                // 另一条更新入口的引导（纯文案，不改变任何跳转行为）。
                Text(
                  'kid_update_hint_capsule'.tr(),
                  style: const TextStyle(color: Colors.white54, fontSize: 16),
                ),
                const SizedBox(height: 26),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: <Widget>[
                    KidOutlineButton(
                      label: laterLabel,
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                    ),
                    const SizedBox(width: 16),
                    KidActionButton(
                      label: confirmLabel,
                      icon: Icons.install_desktop_rounded,
                      autofocus: true,
                      minimumSize: const Size(240, 56),
                      onPressed: () => confirm(dialogContext),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    _showing = false;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
