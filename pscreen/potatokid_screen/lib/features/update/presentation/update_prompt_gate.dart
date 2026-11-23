import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:potatokid_screen/shared/widgets/kid_chrome.dart';
import 'package:pscreen_screen/core/update/app_update_controller.dart';
import 'package:pscreen_screen/core/update/app_update_prompt_store.dart';

/// 普通更新的轻提示门控：挂在 [MaterialApp.builder] 上。
///
/// 新版本下载完成（[AppUpdatePhase.ready]）后只弹一条自动消失的吐司
/// （[SnackBar]），**不再弹模态对话框**——不打断观看，电视遥控也无需在
/// 「稍后 / 立即安装」之间做选择。
///
/// 去重：按 `appId + releaseId` 把「已提示过的版本」持久化到
/// [AppUpdatePromptStore]。同一版本只提示一次，之后重启、回前台复检、
/// 缓存命中重新 ready 都不再提示；出现新版本（新 releaseId）才再提示一次。
///
/// 强制更新不在此列：[AppUpdateState.forceBlocked] 时由 ForceUpdatePage
/// 整页接管，既不吐司也不写去重记录（强更必须每次都拦，不能被「提示过」绕过）。
///
/// 安装入口保持不变：直播页右上角「更新」胶囊、快捷菜单「安装更新」、
/// 「我的 → 版本」行 OK，都能拉起系统安装器。
class UpdatePromptGate extends StatefulWidget {
  const UpdatePromptGate({super.key, required this.child, this.navigatorKey});

  final Widget child;

  /// 根 Navigator 的 key。
  ///
  /// 本组件挂在 [MaterialApp.builder] 上，context 在 Navigator **之上**；
  /// 借用根 Navigator 的 overlay context 才能拿到全局 ScaffoldMessenger。
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  State<UpdatePromptGate> createState() => _UpdatePromptGateState();
}

class _UpdatePromptGateState extends State<UpdatePromptGate> {
  AppUpdatePromptStore? _store;
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    AppUpdateController.instance.addListener(_maybeShow);
    // 检查可能在挂载前就已完成（ready），store 就绪后主动补一次。
    unawaited(_initStore());
  }

  Future<void> _initStore() async {
    try {
      final AppUpdatePromptStore store = await AppUpdatePromptStore.open();
      if (!mounted) return;
      _store = store;
    } catch (error) {
      debugPrint('[UpdatePrompt] 提示记录初始化失败（忽略）: $error');
    }
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
    if (state.forceBlocked) return; // 强更整页接管，不提示也不记去重。
    if (state.result?.hasUpdate != true) return;
    // 只在下载完成后提示：检测到更新时保持静默（进度由胶囊 / 右上角展示）。
    if (state.phase != AppUpdatePhase.ready) return;
    final latest = state.result?.latest;
    final AppUpdatePromptStore? store = _store;
    if (latest == null || store == null) return; // store 未就绪，_initStore 会补
    final String versionKey = latest.releaseId.isNotEmpty
        ? latest.releaseId
        : 'v${latest.version}+${latest.build}';
    if (store.isPrompted(state.result!.appId, versionKey)) {
      debugPrint('[UpdatePrompt] 版本 $versionKey 已提示过，跳过');
      return;
    }
    _showing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _showing = false;
        return;
      }
      unawaited(_showToast(versionKey));
    });
  }

  Future<void> _showToast(String versionKey) async {
    final AppUpdateState state = AppUpdateController.instance.state;
    final latest = state.result?.latest;
    if (latest == null ||
        state.phase != AppUpdatePhase.ready ||
        state.forceBlocked) {
      _showing = false;
      return;
    }
    // 本组件 context 在 Navigator 之上，借用根 Navigator overlay context。
    final BuildContext? navContext =
        widget.navigatorKey?.currentState?.overlay?.context;
    if (navContext == null || !mounted) {
      // 取不到就先不记去重，留给后续状态变化重试。
      _showing = false;
      return;
    }

    // 所有 BuildContext 的使用都放在 await 之前，避免跨异步间隙持有 context。
    final ScaffoldMessengerState? messenger =
        ScaffoldMessenger.maybeOf(navContext) ??
        ScaffoldMessenger.maybeOf(context);
    final bool kid = kidModeOn;
    final String text = kid
        ? 'kid_update_toast_ready'.tr()
        : 'update_toast_ready'.tr(
            namedArgs: <String, String>{
              '__VERSION__': 'v${latest.version}+${latest.build}',
            },
          );

    // 先落盘再展示：写失败也不阻断展示（最多下次多提示一次）。
    try {
      await _store?.markPrompted(state.result!.appId, versionKey);
    } catch (error) {
      debugPrint('[UpdatePrompt] 记录已提示版本失败（忽略）: $error');
    }
    if (!mounted || messenger == null) {
      debugPrint('[UpdatePrompt] 组件已卸载或无 ScaffoldMessenger，跳过展示');
      _showing = false;
      return;
    }
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        kid
            ? kidSnackBar(text, duration: const Duration(seconds: 6))
            : SnackBar(
                content: Text(text),
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 6),
              ),
      );
    debugPrint('[UpdatePrompt] 已吐司提示版本 $versionKey');
    _showing = false;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
