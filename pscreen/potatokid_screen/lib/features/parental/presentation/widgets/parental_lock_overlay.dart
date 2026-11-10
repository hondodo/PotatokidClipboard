import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pscreen_screen/core/media/kid_watch_timer_controller.dart';
import 'package:pscreen_screen/core/parental/parental_quiz.dart';
import 'package:pscreen_screen/core/parental/parental_state_controller.dart';
import 'package:pscreen_screen/core/parental/parental_unlock_code_controller.dart';
import 'package:pscreen_screen/features/msg/application/message_overlay_controller.dart';

import 'device_account_label.dart';
import 'parental_quiz_page.dart';
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
  static const ParentalQuizRepository _quizRepository =
      ParentalQuizRepository();

  /// 当前生效题库（已按年龄合并、并过滤掉电视端无法作答的填空题）。
  List<ParentalQuizQuestion> _quizQuestions = const <ParentalQuizQuestion>[];
  bool _quizLoaded = false;
  bool _quizLoading = false;

  @override
  void initState() {
    super.initState();
    // 到期动作显式接线（方案 3.3「到阈值回调宿主进锁屏」）：到阈值先收起
    // 消息浮层——浮层可见时壳层按键全被它吞走（main_app._handleLogical 首
    // 分支），不收起会让锁屏与浮层抢按键；随后立即重建一次。展示判据仍在
    // build 里读 locked（与控制器通知双路兜底，覆盖重启/解除等全部路径）。
    KidWatchTimerController.instance.onThresholdReached = _onThresholdReached;
    // 锁屏出现 / 解除时维护题库缓存；家长配置（解锁方式、选中孩子）变化时
    // 重新按年龄合并一次（quiz 模式切换为全页题库的判据）。
    KidWatchTimerController.instance.addListener(_onTimerChanged);
    ParentalStateController.instance.addListener(_onParentalChanged);
    if (KidWatchTimerController.instance.locked) {
      unawaited(_ensureQuizLoaded());
    }
  }

  void _onThresholdReached() {
    MessageOverlayController.instance.close();
    if (mounted) setState(() {});
  }

  void _onTimerChanged() {
    if (KidWatchTimerController.instance.locked) {
      unawaited(_ensureQuizLoaded());
    } else if (_quizLoaded || _quizQuestions.isNotEmpty) {
      setState(() {
        _quizLoaded = false;
        _quizQuestions = const <ParentalQuizQuestion>[];
      });
    }
  }

  void _onParentalChanged() {
    if (!KidWatchTimerController.instance.locked) return;
    unawaited(_ensureQuizLoaded());
  }

  /// 先读本地缓存再做服务端刷新；quiz 模式下题库为空即回退短码页
  ///（不做算术兜底）。
  Future<void> _ensureQuizLoaded() async {
    final ParentalStateController parental = ParentalStateController.instance;
    if (!parental.enabled || parental.config.unlockMode != 'quiz') {
      if (_quizLoaded || _quizQuestions.isNotEmpty) {
        if (mounted) {
          setState(() {
            _quizLoaded = false;
            _quizQuestions = const <ParentalQuizQuestion>[];
          });
        }
      }
      return;
    }
    if (_quizLoading) return;
    _quizLoading = true;
    try {
      final Map<String, List<ParentalQuizQuestion>> cache =
          await _quizRepository.readCache();
      _applyBanks(cache, loadComplete: false);
      final Map<String, List<ParentalQuizQuestion>>? remote =
          await _quizRepository.fetchRemote();
      if (!mounted ||
          ParentalStateController.instance.config.unlockMode != 'quiz') {
        return;
      }
      if (remote != null) {
        _applyBanks(remote, loadComplete: true);
      } else {
        setState(() => _quizLoaded = true);
      }
    } finally {
      _quizLoading = false;
    }
  }

  void _applyBanks(
    Map<String, List<ParentalQuizQuestion>> banks, {
    required bool loadComplete,
  }) {
    final List<ParentalQuizQuestion> merged = ParentalQuizSelector.select(
      profiles: ParentalStateController.instance.activeProfiles,
      banks: banks,
    );
    // 电视端只保留可遥控作答的选择题：填空题整题跳过（家长端保留）。
    final List<ParentalQuizQuestion> usable = merged
        .where(
          (ParentalQuizQuestion q) =>
              q.isChoice && q.options.isNotEmpty && q.answers.isNotEmpty,
        )
        .toList(growable: false);
    if (!mounted) return;
    setState(() {
      _quizLoaded = loadComplete || usable.isNotEmpty;
      _quizQuestions = usable;
    });
  }

  @override
  void dispose() {
    KidWatchTimerController.instance.removeListener(_onTimerChanged);
    ParentalStateController.instance.removeListener(_onParentalChanged);
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
      listenable: Listenable.merge(<Listenable>[
        KidWatchTimerController.instance,
        ParentalStateController.instance,
      ]),
      builder: (BuildContext context, _) {
        if (!KidWatchTimerController.instance.locked) {
          return const SizedBox.shrink();
        }
        // 锁屏期间吞掉全部按键（方案 5.2 根按键拦截的锁屏层分支）：本层是
        // MainApp Stack 中 rootOkHandler 的兄弟节点，焦点在锁屏按钮上时按键
        // 不经根分发——放行会上浮 WidgetsApp Shortcuts 触发方向焦点转移，
        // 焦点落到顶部导航条 _TopTab（焦点即切页）导致锁屏下仍能切 Tab。
        // OK/enter 由按钮自身节点先消费（activate），不受此拦截影响。
        // 题库页在内部再挂一个可聚焦节点自行处理方向键/数字键（子节点先于
        // 本拦截节点收到按键），因此不会落到默认焦点遍历。
        return Focus(
          // 本节点只做拦截，不参与焦点遍历，否则方向键可能停在无 UI 的
          // 包装节点上。
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: (FocusNode node, KeyEvent event) =>
              KeyEventResult.handled,
          // 电视遥控的 D-pad / OK 键在 WidgetsApp 默认快捷键之外：这里显式
          // 映射方向焦点与 select，锁屏页的按钮才能被遥控选中和触发。
          child: Shortcuts(
            shortcuts: const <ShortcutActivator, Intent>{
              SingleActivator(LogicalKeyboardKey.arrowDown): NextFocusIntent(),
              SingleActivator(LogicalKeyboardKey.arrowUp):
                  PreviousFocusIntent(),
              SingleActivator(LogicalKeyboardKey.arrowRight): NextFocusIntent(),
              SingleActivator(LogicalKeyboardKey.arrowLeft):
                  PreviousFocusIntent(),
              SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
              SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
              SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
              SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
              SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
            },
            child: _buildLockedContent(),
          ),
        );
      },
    );
  }

  Widget _buildLockedContent() {
    final bool wantsQuiz =
        ParentalStateController.instance.config.unlockMode == 'quiz';
    if (!wantsQuiz) return const _LockScreenPage();
    if (!_quizLoaded) return const _QuizLoadingPage();
    if (_quizQuestions.isNotEmpty) return _buildQuizPage();
    return const _LockScreenPage(quizFallback: true);
  }

  Widget _buildQuizPage() {
    final KidWatchTimerController timer = KidWatchTimerController.instance;
    final int? remainDaily = timer.remainingDailySec;
    return ParentalQuizPage(
      questions: _quizQuestions,
      header: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            '当日剩余：${_LockScreenPageState._fmtDaily(remainDaily)}',
            style: const TextStyle(color: Colors.white70, fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          const DeviceAccountLabel(color: Colors.white54, fontSize: 14),
        ],
      ),
      onSolved: () async {
        KidWatchTimerController.instance.unlock();
        if (mounted) setState(() {});
      },
      onRequestParent: () async {
        final bool ok = await ParentalVerificationSheet.show(
          context,
          forceRemote: true,
        );
        if (!ok || !mounted) return;
        KidWatchTimerController.instance.unlock();
      },
    );
  }
}

class _QuizLoadingPage extends StatelessWidget {
  const _QuizLoadingPage();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color(0xFF234E70),
            Color(0xFF1B425B),
            Color(0xFF16324A),
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.auto_awesome_rounded,
              color: Color(0xFFFFD166),
              size: 56,
            ),
            SizedBox(height: 18),
            Text(
              '题目准备中…',
              style: TextStyle(
                color: Colors.white,
                fontSize: 30,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 18),
            SizedBox(
              width: 180,
              child: LinearProgressIndicator(
                minHeight: 5,
                color: Color(0xFFFFD166),
                backgroundColor: Colors.white24,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 锁屏页：已看/剩余时长 + 6 位短码（含倒计时 / 过期重新请求）+
/// 家长验证入口（`ParentalVerificationSheet`：远程等待 + PIN/算术兜底）。
class _LockScreenPage extends StatefulWidget {
  const _LockScreenPage({this.quizFallback = false});

  /// 家长已选答题模式，但题库为空或只有填空题 → 回退短码，需要明确告知。
  final bool quizFallback;

  @override
  State<_LockScreenPage> createState() => _LockScreenPageState();
}

class _LockScreenPageState extends State<_LockScreenPage> {
  Timer? _ticker;

  /// 锁屏出现时强制把焦点拉到「家长验证解锁」按钮：锁屏前焦点常停在
  /// 顶部导航条/内容区，根按键处理器在锁定期间一律吞键，导致遥控方向键
  /// 与 OK 完全无响应（鼠标可点是因为点击会先赋焦点）。
  final FocusNode _verifyFocus = FocusNode(debugLabel: 'parental-verify');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _verifyFocus.requestFocus();
    });
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
    _verifyFocus.dispose();
    super.dispose();
  }

  Future<void> _reissue() async {
    final KidWatchTimerController timer = KidWatchTimerController.instance;
    final String reason = timer.lockReason.isEmpty
        ? 'threshold'
        : timer.lockReason;
    await ParentalUnlockCodeController.instance.issue(reason);
  }

  Future<void> _openVerify() async {
    final String mode = ParentalStateController.instance.config.unlockMode;
    final bool ok = await ParentalVerificationSheet.show(
      context,
      forceRemote: widget.quizFallback,
      forceArithmetic: !widget.quizFallback && mode == 'remote',
    );
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
    final int? remainDaily = timer.remainingDailySec;
    final ThemeData theme = Theme.of(context);
    final String mode = parental.config.unlockMode;
    final String actionLabel = widget.quizFallback
        ? '请家长帮忙'
        : mode == 'pin'
        ? '输入家长 PIN'
        : '答题解锁';
    final IconData actionIcon = widget.quizFallback
        ? Icons.family_restroom_rounded
        : mode == 'pin'
        ? Icons.pin_outlined
        : Icons.quiz_outlined;

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color(0xFF234E70),
            Color(0xFF1B425B),
            Color(0xFF16324A),
          ],
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: SizedBox(
                width: 920,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(
                      Icons.bedtime_rounded,
                      size: 64,
                      color: Color(0xFFFFD166),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '休息一下吧',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 40,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _lockMessage(timer.lockReason),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 22,
                      ),
                    ),
                    const SizedBox(height: 28),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: <Widget>[
                        SizedBox(
                          width: 430,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                _watchSummary(timer, parental),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                '当日剩余：${_fmtDaily(remainDaily)}',
                                style: const TextStyle(
                                  color: Colors.white60,
                                  fontSize: 18,
                                ),
                              ),
                              if (widget.quizFallback) ...<Widget>[
                                const SizedBox(height: 12),
                                const Text(
                                  '暂时没有可回答的题目，请家长帮忙解锁',
                                  style: TextStyle(
                                    color: Color(0xFFFFD166),
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(
                          height: 116,
                          child: VerticalDivider(
                            width: 48,
                            color: Colors.white24,
                          ),
                        ),
                        Expanded(child: _buildCodeArea(codes, theme)),
                      ],
                    ),
                    const SizedBox(height: 26),
                    const Divider(color: Colors.white24, height: 1),
                    const SizedBox(height: 18),
                    Row(
                      children: <Widget>[
                        const Expanded(
                          child: DeviceAccountLabel(
                            color: Colors.white60,
                            fontSize: 16,
                            textAlign: TextAlign.left,
                          ),
                        ),
                        const SizedBox(width: 24),
                        FilledButton.icon(
                          focusNode: _verifyFocus,
                          autofocus: true,
                          onPressed: _openVerify,
                          icon: Icon(actionIcon),
                          label: Text(actionLabel),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 28,
                              vertical: 16,
                            ),
                            textStyle: const TextStyle(fontSize: 20),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 短码区：有效 → 展示短码与倒计时；未生成/已过期 → 「重新请求」入口
  ///（方案 §4.2：过期后电视端提示重新请求）。
  Widget _buildCodeArea(ParentalUnlockCodeController codes, ThemeData theme) {
    if (codes.active) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          const Text(
            '家长解锁码',
            style: TextStyle(color: Colors.white70, fontSize: 17),
          ),
          const SizedBox(height: 4),
          Text(
            _formatCode(codes.code),
            style: const TextStyle(
              color: Color(0xFFFFD166),
              fontSize: 38,
              letterSpacing: 3,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '等待家长确认 · ${codes.remainingSec} 秒',
            style: const TextStyle(color: Colors.white60, fontSize: 16),
          ),
        ],
      );
    }
    final bool consumed = codes.consumed;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          consumed
              ? '家长已确认'
              : codes.code == null
              ? '正在获取家长解锁码'
              : '解锁码已失效',
          style: theme.textTheme.titleMedium?.copyWith(color: Colors.white70),
        ),
        if (!consumed) ...<Widget>[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _reissue,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('重新获取'),
          ),
        ],
      ],
    );
  }

  static String _lockMessage(String reason) {
    if (reason == 'quietHours') return '现在是休息时间';
    if (reason.startsWith('daily:')) return '今天的观看时间已经用完';
    return '本次观看时间已经结束';
  }

  static String _watchSummary(
    KidWatchTimerController timer,
    ParentalStateController parental,
  ) {
    final List<String> names = timer.activeChildIds
        .map((String id) => parental.config.childById(id)?.name ?? id)
        .toList(growable: false);
    final int seconds = timer.activeChildIds.fold<int>(
      0,
      (int total, String id) => total + timer.sessionSecOf(id),
    );
    final String viewers = switch (names.length) {
      0 => '孩子们',
      1 => names.first,
      2 => '${names.first}和${names.last}',
      _ => '${names.sublist(0, names.length - 1).join('、')}和${names.last}',
    };
    return '$viewers本次共观看了 ${_fmtWatch(seconds)}';
  }

  static String _fmtWatch(int seconds) {
    final int safe = seconds < 0 ? 0 : seconds;
    if (safe < 60) return '$safe 秒';
    final int minutes = safe ~/ 60;
    final int remainSeconds = safe % 60;
    return remainSeconds == 0 ? '$minutes 分钟' : '$minutes 分 $remainSeconds 秒';
  }

  static String _fmtDaily(int? seconds) {
    if (seconds == null) return '未启用';
    final int safe = seconds < 0 ? 0 : seconds;
    if (safe == 0) return '0 分钟';
    if (safe < 60) return '不足 1 分钟';
    final int hours = safe ~/ 3600;
    final int minutes = (safe % 3600) ~/ 60;
    if (hours == 0) return '$minutes 分钟';
    return minutes == 0 ? '$hours 小时' : '$hours 小时 $minutes 分钟';
  }

  static String _formatCode(String? code) {
    final String value = (code ?? '').trim();
    if (value.length != 6) return value;
    return '${value.substring(0, 3)} ${value.substring(3)}';
  }
}
