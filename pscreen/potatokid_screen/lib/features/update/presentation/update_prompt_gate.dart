import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:potatokid_screen/shared/widgets/kid_chrome.dart';
import 'package:pscreen_screen/core/update/app_update_controller.dart';

/// 可用更新弹窗门控：挂载在 [MaterialApp.builder] 上。
///
/// 首次检测到有可用更新（且非强更拦截）时弹一次「发现新版本」对话框；
/// 「立即更新」触发下载/安装（已就绪则直接拉起系统安装器），「稍后」仅关闭。
/// [MaterialApp.router] 组件被重建也只提示一次。
///
/// 下载完成补提示：首次提示选了「稍后」后，等 [AppUpdatePhase.ready] 再补弹一次
/// 「新版本准备好啦」，覆盖「稍后 → 下载完成」这段原本没有任何提示的空白。
/// 补提示是独立的一次性标志，不影响 [_prompted] 的原有语义；用户已在首次提示里
/// 点了「立即更新」或弹窗期间就已下载完成时都不会重复弹窗。
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
  /// 进程级一次性标志：同一次启动「首次发现更新」只提示一次。
  static bool _prompted = false;

  /// 首次提示选了「稍后」，等下载完成再补一次提示。
  static bool _deferredToReady = false;

  /// 下载完成的补提示同一次启动只补一次。
  static bool _readyPrompted = false;

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
    if (state.phase == AppUpdatePhase.installing) return;

    // 首次发现：沿用原有的一次性逻辑；ready 补提示只在「稍后」之后触发。
    final bool firstPrompt = !_prompted;
    final bool readyFollowUp = !firstPrompt &&
        _deferredToReady &&
        !_readyPrompted &&
        state.phase == AppUpdatePhase.ready;
    if (!firstPrompt && !readyFollowUp) return;
    debugPrint(
      '[UpdatePrompt] 触发弹窗 first=$firstPrompt readyFollowUp=$readyFollowUp '
      'hasUpdate=${state.result?.hasUpdate} phase=${state.phase} '
      'nav=${widget.navigatorKey?.currentState != null}',
    );
    _showing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _showing = false;
        return;
      }
      unawaited(_showPrompt(isFirstPrompt: firstPrompt));
    });
  }

  Future<void> _showPrompt({required bool isFirstPrompt}) async {
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
    _prompted = true; // 先置位：本次启动后续状态变化不再触发「首次」提示。
    if (state.phase == AppUpdatePhase.ready) {
      // 首次弹窗时就已经下载完成（缓存命中）：不需要再补一次 ready 提示。
      _readyPrompted = true;
    }

    final bool ready = state.phase == AppUpdatePhase.ready;
    final bool kid = kidModeOn;
    final int? bytes = state.result?.download?.size;
    final String sizeText = bytes != null && bytes > 0
        ? '（约 ${(bytes / 1024 / 1024).toStringAsFixed(1)}MB）'
        : '';
    final String title = kid
        ? (ready
              ? 'kid_update_title_ready'.tr()
              : 'kid_update_title_new'.tr())
        : (ready ? '新版本已就绪' : '发现新版本');
    final String body = kid
        ? (ready
              ? 'kid_update_body_ready'.tr()
              : 'kid_update_body_new'.tr())
        : ready
        ? '新版本 v${latest.version}+${latest.build} 已下载完成，是否立即安装？'
        : '检测到新版本 v${latest.version}+${latest.build}$sizeText，是否立即更新？';
    final String laterLabel = kid ? 'kid_update_later'.tr() : '稍后';
    final String confirmLabel = kid
        ? (ready
              ? 'kid_update_install'.tr()
              : 'kid_update_download'.tr())
        : (ready ? '立即安装' : '立即更新');

    /// 与原实现一致：ready 直接安装，否则下载完立即安装。
    Future<void> confirm(BuildContext dialogCtx) async {
      Navigator.of(dialogCtx).pop(true);
      if (ready) {
        await controller.install();
        return;
      }
      await controller.ensureDownloadedNow();
      if (controller.state.phase == AppUpdatePhase.ready) {
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
    }

    if (!mounted) {
      _showing = false;
      return;
    }
    final bool? confirmed = await showDialog<bool>(
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

    // 只有「首次提示被推迟」并且下载还在进行时才挂起补提示。
    // 弹窗里已经点了「立即更新」（下载/安装由本弹窗接管）或弹窗期间就已 ready，
    // 都不再补弹，避免连续两次模态弹窗。
    if (isFirstPrompt) {
      if (confirmed == true ||
          controller.state.phase == AppUpdatePhase.ready ||
          controller.state.phase == AppUpdatePhase.installing) {
        _readyPrompted = true;
      } else {
        _deferredToReady = true;
      }
    } else {
      _deferredToReady = false;
      _readyPrompted = true;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
