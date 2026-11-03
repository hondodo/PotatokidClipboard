import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pscreen_screen/core/media/kid_watch_timer_controller.dart';
import 'package:pscreen_screen/core/parental/parental_state_controller.dart';
import 'package:pscreen_screen/core/parental/parental_unlock_code_controller.dart';
import 'package:pscreen_screen/features/msg/application/message_overlay_controller.dart';

import 'parental_verification_sheet.dart';

/// 儿童模式锁屏覆盖层（阶段 2：远程解锁短码 + ParentalVerificationSheet）。
///
/// 挂在 `MainApp` 最上层（盖住顶部导航条、悬浮遥控器与消息浮层），展示判据
/// 统一读 [KidWatchTimerController.locked]：
/// - 计时到阈值：`_fireThreshold` → notifyListeners → 本层重建展示；
/// - 重启保持：启动时 DI（ParentalModule）已 `ensureLoaded()`，首帧读到
///   `locked == true` 直接进锁屏；
/// - 解除（远程命令 / 本地验证 / `clearAll` / 家长关模式）同样经控制器
///   通知收起，不残留。
///
/// 短码生成与双发由 [ParentalUnlockCodeController] 负责（DI 挂到计时器，
/// 锁屏出现即签发），本层只负责展示、倒计时与「重新请求」入口。
class ParentalLockOverlay extends StatefulWidget {
  const ParentalLockOverlay({super.key});

  @override
  State<ParentalLockOverlay> createState() => _ParentalLockOverlayState();
}

class _ParentalLockOverlayState extends State<ParentalLockOverlay> {
  @override
  void initState() {
    super.initState();
    // 到期动作显式接线（方案 3.3「到阈值回调宿主进锁屏」）：到阈值先收起
    // 消息浮层——浮层可见时壳层按键全被它吞走（main_app._handleLogical 首
    // 分支），不收起会让锁屏与浮层抢按键；随后立即重建一次。展示判据仍在
    // build 里读 locked（与控制器通知双路兜底，覆盖重启/解除等全部路径）。
    KidWatchTimerController.instance.onThresholdReached = _onThresholdReached;
  }

  void _onThresholdReached() {
    MessageOverlayController.instance.close();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    // 只清理自己挂的回调，不覆盖后续注入（远程解锁命令走控制器通知）。
    if (KidWatchTimerController.instance.onThresholdReached ==
        _onThresholdReached) {
      KidWatchTimerController.instance.onThresholdReached = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: KidWatchTimerController.instance,
      builder: (BuildContext context, _) {
        if (!KidWatchTimerController.instance.locked) {
          return const SizedBox.shrink();
        }
        // 锁屏期间吞掉全部按键（方案 5.2 根按键拦截的锁屏层分支）：本层是
        // MainApp Stack 中 rootOkHandler 的兄弟节点，焦点在锁屏按钮上时按键
        // 不经根分发——放行会上浮 WidgetsApp Shortcuts 触发方向焦点转移，
        // 焦点落到顶部导航条 _TopTab（焦点即切页）导致锁屏下仍能切 Tab。
        // OK/enter 由按钮自身节点先消费（activate），不受此拦截影响。
        return Focus(
          onKeyEvent: (FocusNode node, KeyEvent event) =>
              KeyEventResult.handled,
          child: const _LockScreenPage(),
        );
      },
    );
  }
}

/// 锁屏页：已看/剩余时长 + 6 位短码（含倒计时 / 过期重新请求）+
/// 家长验证入口（`ParentalVerificationSheet`：远程等待 + PIN/算术兜底）。
class _LockScreenPage extends StatefulWidget {
  const _LockScreenPage();

  @override
  State<_LockScreenPage> createState() => _LockScreenPageState();
}

class _LockScreenPageState extends State<_LockScreenPage> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // 短码状态（签发/消费/过期）变化即时刷新，不等 1s 倒计时 ticker。
    ParentalUnlockCodeController.instance.addListener(_onCodesChanged);
    // 每秒刷新短码倒计时（锁屏期间本页常驻，解锁即卸载停表）。
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  void _onCodesChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    ParentalUnlockCodeController.instance.removeListener(_onCodesChanged);
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _reissue() async {
    final KidWatchTimerController timer = KidWatchTimerController.instance;
    final String reason =
        timer.lockReason.isEmpty ? 'threshold' : timer.lockReason;
    await ParentalUnlockCodeController.instance.issue(reason);
  }

  Future<void> _openVerify() async {
    final bool ok = await ParentalVerificationSheet.show(context);
    // 远程路径由命令执行器解锁（sheet 观察到锁解除后返回 true），
    // 本地路径（PIN/算术）在此解除；unlock 对未锁状态幂等。
    if (!ok || !mounted) return;
    KidWatchTimerController.instance.unlock();
  }

  @override
  Widget build(BuildContext context) {
    final KidWatchTimerController timer = KidWatchTimerController.instance;
    final ParentalStateController parental = ParentalStateController.instance;
    final ParentalUnlockCodeController codes =
        ParentalUnlockCodeController.instance;
    final int? remainSession = timer.remainingSessionSec;
    final int? remainDaily = timer.remainingDailySec;
    final ThemeData theme = Theme.of(context);
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.lock_outline,
                size: 72,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                '观看时间已到',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(color: Colors.white),
              ),
              const SizedBox(height: 20),
              // 剩余取「当前组合中最先到阈值者」（remaining* 内部逐人取最小）。
              Text(
                '单次剩余：${remainSession == null ? '未启用' : _fmt(remainSession)}'
                '　　当日剩余：${remainDaily == null ? '未启用' : _fmt(remainDaily)}',
                style: theme.textTheme.titleMedium
                    ?.copyWith(color: Colors.white70),
              ),
              const SizedBox(height: 12),
              // 逐人已看（分账）：锁屏展示当前组合内每个孩子的 session/daily。
              for (final String id in timer.activeChildIds)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '${_nameOf(parental, id)}：已看 ${_fmt(timer.sessionSecOf(id))}'
                    '（当日 ${_fmt(timer.dailySecOf(id))}）',
                    style: theme.textTheme.bodyLarge
                        ?.copyWith(color: Colors.white70),
                  ),
                ),
              const SizedBox(height: 20),
              ..._buildCodeArea(codes, theme),
              const SizedBox(height: 24),
              FilledButton(
                autofocus: true,
                onPressed: _openVerify,
                child: const Text('家长验证解锁'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 短码区：有效 → 展示短码与倒计时；未生成/已过期 → 「重新请求」入口
  ///（方案 §4.2：过期后电视端提示重新请求）。
  List<Widget> _buildCodeArea(
    ParentalUnlockCodeController codes,
    ThemeData theme,
  ) {
    if (codes.active) {
      return <Widget>[
        Text(
          '解锁码 ${codes.code}',
          style: const TextStyle(
            color: Colors.amber,
            fontSize: 32,
            letterSpacing: 6,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          '请在手机上确认解锁',
          style: TextStyle(color: Colors.amber, fontSize: 18),
        ),
        const SizedBox(height: 4),
        Text(
          '有效期 ${codes.remainingSec} 秒',
          style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white70),
        ),
      ];
    }
    final bool consumed = codes.consumed;
    return <Widget>[
      Text(
        consumed
            ? '解锁已确认'
            : codes.code == null
                ? '尚未生成解锁码'
                : '解锁码已过期',
        style: theme.textTheme.titleMedium?.copyWith(color: Colors.white70),
      ),
      if (!consumed) ...<Widget>[
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: _reissue,
          child: const Text('重新请求解锁码'),
        ),
      ],
    ];
  }

  /// 时长展示：`X 分 Y 秒`（负值按 0 处理——到阈值后剩余即为 0/负）。
  static String _fmt(int sec) {
    final int s = sec < 0 ? 0 : sec;
    return s < 60 ? '$s 秒' : '${s ~/ 60} 分 ${s % 60} 秒';
  }

  static String _nameOf(ParentalStateController parental, String id) =>
      parental.config.childById(id)?.name ?? id;
}
