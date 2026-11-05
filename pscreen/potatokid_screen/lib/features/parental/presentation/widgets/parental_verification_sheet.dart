import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pscreen_screen/core/media/kid_watch_timer_controller.dart';
import 'package:pscreen_screen/core/parental/parental_attempt_gate.dart';
import 'package:pscreen_screen/core/parental/parental_config.dart';
import 'package:pscreen_screen/core/parental/parental_quiz.dart';
import 'package:pscreen_screen/core/parental/parental_state_controller.dart';
import 'package:pscreen_screen/core/parental/parental_unlock_code_controller.dart';

/// 家长验证层（锁屏解锁与后续选人页 `locked` 闸门共用的统一入口）。
///
/// 验证方式按 [ParentalConfig.unlockMode]（方案 §4.2 离线兜底）：
/// - `remote`：等待手机下发 `parental_unlock` 命令（展示等待状态与短码），
///   **同时展示算术题作断线兜底**（否则断线死锁）；
/// - `pin`：4 位数字输入（PIN 读 config；未配置 PIN 时回退算术题）；
/// - `arith`：三选一随机一位数加法。
///
/// 防爆破：连续错 5 次本地锁定 60s（[ParentalAttemptGate]，计数持久化、
/// 重启不清）。
///
/// 本组件只做「验证」并返回是否通过，**不直接解锁**——调用方按场景处理
///（锁屏页收到 true 后调 `KidWatchTimerController.unlock()`；选人页闸门
/// 阶段 3 接入时用于放行进入）。远程路径由命令执行器直接解锁，本层监听
/// 到锁解除后自行收起（返回 true）。
class ParentalVerificationSheet extends StatefulWidget {
  const ParentalVerificationSheet({super.key});

  /// 统一入口：弹出验证层；返回 true = 验证通过（含观察到远程解锁）。
  static Future<bool> show(BuildContext context) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) => const ParentalVerificationSheet(),
    );
    return ok ?? false;
  }

  @override
  State<ParentalVerificationSheet> createState() =>
      _ParentalVerificationSheetState();
}

class _ParentalVerificationSheetState extends State<ParentalVerificationSheet> {
  final TextEditingController _pinCtrl = TextEditingController();
  final Random _random = Random();

  /// 打开时锁屏是否成立：仅此时监听远程解锁边沿（选人页 `locked` 闸门
  /// 场景打开时未锁，不监听，避免被无关状态误关）。
  late bool _watchRemoteUnlock;
  late bool _prevLocked;

  /// 已经发起关闭：弹窗关闭动画期间仍可能收到控制器通知，
  /// 必须忽略，否则会二次 pop 把底下的页面弹掉。
  bool _closing = false;

  Timer? _ticker;
  String _pinError = '';
  String _arithError = '';
  int _arithA = 0;
  int _arithB = 0;
  List<int> _arithOptions = const <int>[];

  // ---- 答题解锁（unlockMode == 'quiz'） ----
  final ParentalQuizRepository _quizRepo = const ParentalQuizRepository();
  final TextEditingController _fillCtrl = TextEditingController();
  Map<String, List<ParentalQuizQuestion>> _quizBanks =
      <String, List<ParentalQuizQuestion>>{};
  List<ParentalQuizQuestion> _quizQuestions = const <ParentalQuizQuestion>[];

  /// 服务端拉取已结束（成功或失败）；结束前若缓存为空显示「加载中」。
  bool _quizLoaded = false;
  int _quizIndex = 0;
  final Set<int> _quizSelected = <int>{};
  String _quizError = '';

  /// 远程题库刷新到达时，若用户还没作答则换用最新题库（已作答不打断）。
  bool _quizTouched = false;

  @override
  void initState() {
    super.initState();
    _watchRemoteUnlock = KidWatchTimerController.instance.locked;
    _prevLocked = _watchRemoteUnlock;
    if (_watchRemoteUnlock) {
      KidWatchTimerController.instance.addListener(_onTimerNotify);
    }
    // 短码状态（重新请求/被消费）变化即时刷新，不等 1s 倒计时 ticker。
    ParentalUnlockCodeController.instance.addListener(_onCodesChanged);
    _newArith();
    // 答题解锁：先用本地缓存立即可答，再后台刷新题库。
    if (ParentalStateController.instance.config.unlockMode == 'quiz') {
      unawaited(_loadQuiz());
    }
    // 闸门持久化加载（DI 已加载时幂等）；加载后刷新一次以还原锁定态。
    unawaited(
      ParentalAttemptGate.instance.ensureLoaded().then((_) {
        if (mounted) setState(() {});
      }),
    );
    // 每秒刷新：短码倒计时与锁定剩余时间。
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    ParentalUnlockCodeController.instance.removeListener(_onCodesChanged);
    _ticker?.cancel();
    _stopWatchingRemoteUnlock();
    _pinCtrl.dispose();
    _fillCtrl.dispose();
    super.dispose();
  }

  /// 短码状态变化 → 刷新展示（重新请求后立即出码）。
  void _onCodesChanged() {
    if (mounted) setState(() {});
  }

  /// 停止观察远程解锁（本地验证通过 / 用户关闭 / 已开始收起时调用）。
  void _stopWatchingRemoteUnlock() {
    if (!_watchRemoteUnlock) return;
    KidWatchTimerController.instance.removeListener(_onTimerNotify);
    _watchRemoteUnlock = false;
  }

  /// 统一收口：只允许关闭一次，并立即停止监听控制器。
  void _close(bool result) {
    if (_closing || !mounted) return;
    _closing = true;
    _stopWatchingRemoteUnlock();
    Navigator.of(context).pop(result);
  }

  /// 远程解锁观察：锁由成立变为解除 → 验证通过，收起。
  void _onTimerNotify() {
    if (_closing) return;
    final bool locked = KidWatchTimerController.instance.locked;
    if (_prevLocked && !locked && mounted) {
      _close(true);
      return;
    }
    _prevLocked = locked;
  }

  @override
  Widget build(BuildContext context) {
    final ParentalConfig config = ParentalStateController.instance.config;
    final ParentalAttemptGate gate = ParentalAttemptGate.instance;
    final String mode = config.unlockMode; // remote | pin | arith | quiz
    final bool usePin = mode == 'pin' && config.pin.isNotEmpty;
    final bool useQuiz = mode == 'quiz';
    final TextTheme textTheme = Theme.of(context).textTheme;

    return PopScope(
      canPop: true,
      // 返回键 / 点击遮罩关闭时也立即停止监听，避免关闭动画期间被控制器
      // 通知二次 pop。
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) return;
        _closing = true;
        _stopWatchingRemoteUnlock();
      },
      child: Shortcuts(
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.arrowDown): NextFocusIntent(),
          SingleActivator(LogicalKeyboardKey.arrowUp): PreviousFocusIntent(),
          SingleActivator(LogicalKeyboardKey.arrowRight): NextFocusIntent(),
          SingleActivator(LogicalKeyboardKey.arrowLeft): PreviousFocusIntent(),
          SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        child: FocusTraversalGroup(
          child: Dialog(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              // 答题模式最多 10 个选项，小屏 / 电视安全区下会超屏；
              // 统一可滚动，遥控换焦点时 Scrollable 会自动跟随。
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Icon(
                          Icons.lock_outline,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text('家长验证', style: textTheme.titleLarge),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (gate.locked) ...<Widget>[
                      Text(
                        '连续错误次数过多，已锁定 ${gate.remainingLockSec} 秒',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (mode == 'remote') ..._buildRemoteSection(gate),
                    if (useQuiz) ..._buildQuizSection(gate, textTheme),
                    if (usePin) ..._buildPinSection(gate, textTheme),
                    // arith 模式，或 pin 未配置、remote 断线兜底 → 算术题。
                    // 答题模式只在题库为空时回退算术题（见 _buildQuizSection）。
                    if (!useQuiz &&
                        (mode == 'arith' ||
                            (mode == 'pin' && !usePin) ||
                            mode == 'remote'))
                      ..._buildArithSection(gate, textTheme),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () => _close(false),
                      child: const Text('关闭'),
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

  // ---- quiz：儿童题库答题解锁 ----

  /// 先读缓存（离线也能答），再后台刷新服务端题库。
  Future<void> _loadQuiz() async {
    final Map<String, List<ParentalQuizQuestion>> cached =
        await _quizRepo.readCache();
    if (!mounted) return;
    setState(() {
      _quizBanks = cached;
      if (_quizQuestions.isEmpty) _quizQuestions = _selectQuestions();
    });
    final Map<String, List<ParentalQuizQuestion>>? remote =
        await _quizRepo.fetchRemote();
    if (!mounted) return;
    setState(() {
      if (remote != null) _quizBanks = remote;
      // 已开始作答则不打断当前题；否则换成最新题库。
      if (!_quizTouched) {
        _quizQuestions = _selectQuestions();
        _quizIndex = 0;
        _quizSelected.clear();
        _fillCtrl.clear();
      }
      _quizLoaded = true;
    });
  }

  List<ParentalQuizQuestion> _selectQuestions() {
    final ParentalStateController state = ParentalStateController.instance;
    // 锁屏 / 选人闸门阶段可能还没有「当前孩子」，此时按全部档案取题库，
    // 否则答题模式在进房前会被误判为空题库而回退算术题。
    final List<ChildProfile> profiles = state.activeProfiles.isNotEmpty
        ? state.activeProfiles
        : state.config.children;
    return ParentalQuizSelector.select(profiles: profiles, banks: _quizBanks);
  }

  List<Widget> _buildQuizSection(
    ParentalAttemptGate gate,
    TextTheme textTheme,
  ) {
    if (_quizQuestions.isEmpty) {
      if (!_quizLoaded) {
        return <Widget>[
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          Text(
            '正在加载题库…',
            textAlign: TextAlign.center,
            style: textTheme.bodySmall,
          ),
        ];
      }
      // 所选孩子全部没有题库 → 回退算术题，避免孩子永远打不开电视。
      return <Widget>[
        Text(
          '所选孩子还没有题库，已回退算术题',
          textAlign: TextAlign.center,
          style: textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        ..._buildArithSection(gate, textTheme),
      ];
    }

    final ParentalQuizQuestion q =
        _quizQuestions[_quizIndex % _quizQuestions.length];
    final List<Widget> children = <Widget>[
      Text(
        '第 ${_quizIndex + 1} / ${_quizQuestions.length} 题',
        textAlign: TextAlign.center,
        style: textTheme.bodySmall,
      ),
      if (q.prompt.isNotEmpty) ...<Widget>[
        const SizedBox(height: 4),
        Text(q.prompt, textAlign: TextAlign.center, style: textTheme.titleLarge),
      ],
      if (q.promptImageUrl.isNotEmpty) _buildQuizImage(q.promptImageUrl),
      const SizedBox(height: 12),
      if (q.isChoice)
        ..._buildQuizChoice(gate, q)
      else
        ..._buildQuizFill(gate, q, textTheme),
    ];
    if (_quizError.isNotEmpty) {
      children.addAll(<Widget>[
        const SizedBox(height: 8),
        Text(
          _quizError,
          textAlign: TextAlign.center,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ]);
    }
    return children;
  }

  Widget _buildQuizImage(String url) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        url,
        height: 140,
        fit: BoxFit.contain,
        errorBuilder: (BuildContext context, Object error, StackTrace? stack) =>
            const Icon(Icons.broken_image_outlined, size: 48),
      ),
    ),
  );

  List<Widget> _buildQuizChoice(
    ParentalAttemptGate gate,
    ParentalQuizQuestion q,
  ) {
    final ThemeData theme = Theme.of(context);
    final List<Widget> children = <Widget>[];
    for (int i = 0; i < q.options.length; i++) {
      final ParentalQuizOption option = q.options[i];
      final bool selected = _quizSelected.contains(i);
      children.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: OutlinedButton(
            autofocus: i == 0,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
              backgroundColor: selected
                  ? theme.colorScheme.primaryContainer
                  : null,
            ),
            onPressed: gate.locked ? null : () => unawaited(_onOption(q, i)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                if (q.multiple) ...<Widget>[
                  Icon(
                    selected
                        ? Icons.check_box
                        : Icons.check_box_outline_blank,
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                ],
                if (option.image.isNotEmpty) ...<Widget>[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Image.network(
                      ParentalQuizQuestion.resolveImageUrl(option.image),
                      height: 44,
                      fit: BoxFit.contain,
                      errorBuilder: (
                        BuildContext context,
                        Object error,
                        StackTrace? stack,
                      ) => const Icon(Icons.broken_image_outlined, size: 22),
                    ),
                  ),
                  if (option.text.isNotEmpty) const SizedBox(width: 8),
                ],
                if (option.text.isNotEmpty)
                  Flexible(
                    child: Text(option.text, textAlign: TextAlign.center),
                  ),
              ],
            ),
          ),
        ),
      );
    }
    if (q.multiple) {
      children.add(
        FilledButton(
          onPressed: gate.locked || _quizSelected.isEmpty
              ? null
              : () => unawaited(_submitQuizChoice(q)),
          child: const Text('提交答案'),
        ),
      );
    }
    return children;
  }

  List<Widget> _buildQuizFill(
    ParentalAttemptGate gate,
    ParentalQuizQuestion q,
    TextTheme textTheme,
  ) {
    return <Widget>[
      TextField(
        controller: _fillCtrl,
        autofocus: true,
        enabled: !gate.locked,
        textAlign: TextAlign.center,
        decoration: const InputDecoration(
          labelText: '输入答案',
          border: OutlineInputBorder(),
          isDense: true,
        ),
        onSubmitted: (_) => unawaited(_submitQuizFill(q)),
      ),
      const SizedBox(height: 8),
      FilledButton(
        onPressed: gate.locked ? null : () => unawaited(_submitQuizFill(q)),
        child: const Text('提交答案'),
      ),
      const SizedBox(height: 6),
      Text(
        '可用遥控方向键在电视输入法中选择文字',
        textAlign: TextAlign.center,
        style: textTheme.bodySmall,
      ),
    ];
  }

  Future<void> _onOption(ParentalQuizQuestion q, int index) async {
    if (ParentalAttemptGate.instance.locked) return;
    _quizTouched = true;
    if (!q.multiple) {
      _quizSelected
        ..clear()
        ..add(index);
      await _submitQuizChoice(q);
      return;
    }
    setState(() {
      if (!_quizSelected.remove(index)) _quizSelected.add(index);
      _quizError = '';
    });
  }

  Future<void> _submitQuizChoice(ParentalQuizQuestion q) async {
    if (q.multiple && _quizSelected.isEmpty) return;
    final bool correct =
        _quizSelected.length == q.answers.length &&
        _quizSelected.every(q.answers.contains);
    await _onQuizAnswered(correct);
  }

  Future<void> _submitQuizFill(ParentalQuizQuestion q) async {
    final String raw = _fillCtrl.text.trim();
    if (raw.isEmpty) return;
    final String answer = _normalizeAnswer(raw);
    final bool correct = q.accept.any(
      (String item) => _normalizeAnswer(item) == answer,
    );
    await _onQuizAnswered(correct);
  }

  /// 判题结果：答对立即解锁；答错计一次失败并换下一题（沿用 5 次锁定 60s）。
  Future<void> _onQuizAnswered(bool correct) async {
    _quizTouched = true;
    final ParentalAttemptGate gate = ParentalAttemptGate.instance;
    if (correct) {
      await gate.recordSuccess();
      _close(true);
      return;
    }
    await gate.recordFailure();
    if (!mounted) return;
    setState(() {
      _quizError =
          '回答错误，还可尝试 '
          '${ParentalAttemptGate.maxFailures - gate.failCount} 次';
      _quizIndex = _quizQuestions.isEmpty
          ? 0
          : (_quizIndex + 1) % _quizQuestions.length;
      _quizSelected.clear();
      _fillCtrl.clear();
    });
  }

  /// 填空判题归一：去首尾空格、忽略大小写与内部空白。
  static String _normalizeAnswer(String raw) =>
      raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');

  // ---- remote：短码等待 + 重新请求 ----

  List<Widget> _buildRemoteSection(ParentalAttemptGate gate) {
    final ParentalUnlockCodeController codes =
        ParentalUnlockCodeController.instance;
    final List<Widget> children = <Widget>[];
    if (codes.active) {
      children.addAll(<Widget>[
        Text(
          '解锁码 ${codes.code}',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.amber,
            fontSize: 28,
            letterSpacing: 6,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '请在手机上确认解锁（有效期 ${codes.remainingSec} 秒）',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ]);
    } else if (codes.consumed) {
      children.add(const Text('解锁已确认', textAlign: TextAlign.center));
    } else {
      children.addAll(<Widget>[
        Text(
          codes.code == null ? '尚未生成解锁码' : '解锁码已过期',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: gate.locked ? null : _reissue,
          child: const Text('重新请求解锁码'),
        ),
      ]);
    }
    children.add(const SizedBox(height: 12));
    children.add(Divider(height: 1, color: Theme.of(context).dividerColor));
    children.add(const SizedBox(height: 12));
    children.add(
      Text('断线兜底：在本机完成下方算术题即可解锁', style: Theme.of(context).textTheme.bodySmall),
    );
    children.add(const SizedBox(height: 8));
    return children;
  }

  Future<void> _reissue() async {
    final KidWatchTimerController timer = KidWatchTimerController.instance;
    final String reason = timer.lockReason.isEmpty
        ? 'threshold'
        : timer.lockReason;
    await ParentalUnlockCodeController.instance.issue(reason);
  }

  // ---- pin：4 位数字输入 ----

  List<Widget> _buildPinSection(ParentalAttemptGate gate, TextTheme textTheme) {
    return <Widget>[
      TextField(
        controller: _pinCtrl,
        autofocus: true,
        enabled: !gate.locked,
        keyboardType: TextInputType.number,
        maxLength: 4,
        obscureText: true,
        decoration: InputDecoration(
          labelText: '输入 4 位 PIN',
          isDense: true,
          counterText: '',
          errorText: _pinError.isEmpty ? null : _pinError,
        ),
        onSubmitted: (_) => _submitPin(),
      ),
      const SizedBox(height: 8),
      FilledButton(
        onPressed: gate.locked ? null : _submitPin,
        child: const Text('确认'),
      ),
      const SizedBox(height: 12),
      Text('忘记 PIN 可让家长在后台重设', style: textTheme.bodySmall),
      const SizedBox(height: 12),
    ];
  }

  Future<void> _submitPin() async {
    final ParentalAttemptGate gate = ParentalAttemptGate.instance;
    if (gate.locked) return;
    final String entered = _pinCtrl.text.trim();
    if (entered.isNotEmpty &&
        entered == ParentalStateController.instance.config.pin) {
      await gate.recordSuccess();
      _close(true);
      return;
    }
    await gate.recordFailure();
    if (!mounted) return;
    setState(() {
      _pinCtrl.clear();
      _pinError =
          'PIN 错误，还可尝试 '
          '${ParentalAttemptGate.maxFailures - gate.failCount} 次';
    });
  }

  // ---- arith：三选一随机一位数加法 ----

  List<Widget> _buildArithSection(
    ParentalAttemptGate gate,
    TextTheme textTheme,
  ) {
    return <Widget>[
      Text(
        '$_arithA + $_arithB = ?',
        textAlign: TextAlign.center,
        style: textTheme.headlineSmall,
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 12,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: <Widget>[
          for (final int option in _arithOptions)
            SizedBox(
              width: 96,
              child: OutlinedButton(
                autofocus: option == _arithOptions.first,
                onPressed: gate.locked
                    ? null
                    : () => unawaited(_submitArith(option)),
                child: Text('$option'),
              ),
            ),
        ],
      ),
      if (_arithError.isNotEmpty) ...<Widget>[
        const SizedBox(height: 8),
        Text(
          _arithError,
          textAlign: TextAlign.center,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ],
    ];
  }

  Future<void> _submitArith(int value) async {
    final ParentalAttemptGate gate = ParentalAttemptGate.instance;
    if (gate.locked) return;
    if (value == _arithA + _arithB) {
      await gate.recordSuccess();
      _close(true);
      return;
    }
    await gate.recordFailure();
    if (!mounted) return;
    setState(() {
      _arithError =
          '回答错误，还可尝试 '
          '${ParentalAttemptGate.maxFailures - gate.failCount} 次';
      _newArith(); // 换一题，防背答案。
    });
  }

  /// 生成一位数加法题（0~9 + 0~9）与三个互异选项（正确和 ±1/±2，夹在 0~18）。
  void _newArith() {
    _arithA = _random.nextInt(10);
    _arithB = _random.nextInt(10);
    final int sum = _arithA + _arithB;
    final Set<int> options = <int>{sum};
    for (final int delta in <int>[1, -1, 2, -2]) {
      final int v = sum + delta;
      if (v >= 0 && v <= 18) options.add(v);
      if (options.length == 3) break;
    }
    _arithOptions = options.toList(growable: false)..shuffle(_random);
  }
}
