import 'dart:async';
import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pscreen_screen/core/parental/parental_attempt_gate.dart';
import 'package:pscreen_screen/core/parental/parental_quiz.dart';

/// 全屏题库作答页（电视横屏 + 遥控为主，观看者是儿童）。
///
/// 与 `ParentalVerificationSheet` 里的题库 UI 刻意分离：那一套是给家长端/
/// 触屏兜底用的，单选点一下就提交；本页面向儿童遥控作答，规则是：
/// - 方向键只在网格内按坐标移动焦点，OK 只改选中/勾选，**不提交**；
/// - 数字键 `1`~`9` 选第 1~9 项、`0` 选第 10 项，同样只选中不提交；
/// - 焦点移到「确认答案」按钮后按 OK 才判题；
/// - 焦点初始落在第一个选项；入参已由调用方过滤掉填空题型。
///
/// 判题沿用 [ParentalAttemptGate]：答错计一次失败并换下一题（5 次锁 60s），
/// 答对回调 [onSolved]（由锁屏层负责 `KidWatchTimerController.unlock()`）。
class ParentalQuizPage extends StatefulWidget {
  const ParentalQuizPage({
    super.key,
    required this.questions,
    required this.onSolved,
    required this.onRequestParent,
    this.header,
  });

  /// 已过滤（仅 choice、选项非空）、按年龄合并后的题库。
  final List<ParentalQuizQuestion> questions;

  /// 答对（已 `recordSuccess`）后的回调。
  final Future<void> Function() onSolved;

  /// 右上角「请求家长解锁」入口（打开短码/远程解锁流程）。
  /// 完成后本页收回焦点，保证方向键继续落在题库 UI 上。
  final Future<void> Function() onRequestParent;

  /// 顶部附加信息（锁屏页的剩余时长等）。
  final Widget? header;

  @override
  State<ParentalQuizPage> createState() => _ParentalQuizPageState();
}

/// 焦点分区：网格 / 确认按钮 / 右上角请求入口。
enum _QuizFocusArea { grid, confirm, request }

class _ParentalQuizPageState extends State<ParentalQuizPage> {
  int _index = 0;
  final Set<int> _selected = <int>{};
  String _error = '';
  _QuizFocusArea _area = _QuizFocusArea.grid;
  int _row = 0;
  int _col = 0;

  /// 本页自持焦点节点：锁屏层外层 Focus `canRequestFocus:false` 只做吞键，
  /// 必须确保按键先落到本页（否则会漏到根分发，返回键可能绕过锁屏）。
  final FocusNode _focusNode = FocusNode(debugLabel: 'parental-quiz');

  /// 低饱和浅色循环（10 种）；背景透明度按序号在 12%~18% 间变化。
  static const List<Color> _palette = <Color>[
    Color(0xFFFFE0B2),
    Color(0xFFB2DFDB),
    Color(0xFFC5CAE9),
    Color(0xFFF8BBD0),
    Color(0xFFDCEDC8),
    Color(0xFFFFF59D),
    Color(0xFFB3E5FC),
    Color(0xFFE1BEE7),
    Color(0xFFFFCCBC),
    Color(0xFFD7CCC8),
  ];

  /// 行数（按选项数固定排布；文字过长时由 [_columns] 降列后重算）。
  static int _baseColumns(int count) {
    if (count <= 2) return 2;
    if (count == 3) return 3;
    if (count == 4) return 2;
    if (count <= 6) return 3;
    if (count <= 8) return 4;
    return 5;
  }

  /// 选项文字较长时自动降列数，避免每格文字被挤成多行。
  static int _columns(List<ParentalQuizOption> options) {
    int cols = _baseColumns(options.length);
    int maxLen = 0;
    for (final ParentalQuizOption option in options) {
      maxLen = math.max(maxLen, option.text.length);
    }
    if (maxLen >= 14 && cols > 1) cols -= 1;
    if (maxLen >= 24 && cols > 1) cols -= 1;
    return cols;
  }

  ParentalQuizQuestion get _question =>
      widget.questions[_index % widget.questions.length];

  int get _rows => (widget.questions.isEmpty
      ? 1
      : (_question.options.length + _columns(_question.options) - 1) ~/
            _columns(_question.options));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
    unawaited(
      ParentalAttemptGate.instance.ensureLoaded().then((_) {
        if (mounted) setState(() {});
      }),
    );
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  /// 打开「请求家长解锁」流程；弹层关闭后把焦点收回本页。
  void _requestParent() {
    unawaited(_openParentFlow());
  }

  Future<void> _openParentFlow() async {
    try {
      await widget.onRequestParent();
    } finally {
      if (mounted) _focusNode.requestFocus();
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      // 吞掉按键抬起，避免向锁屏层/根分发上浮触发其它动作。
      return KeyEventResult.handled;
    }
    final LogicalKeyboardKey key = event.logicalKey;
    final int? digit = _digitOf(key);
    if (digit != null) {
      _selectByDigit(digit);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      _move(key);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.gameButtonA) {
      _activate();
      return KeyEventResult.handled;
    }
    // 返回键 / 菜单键等：锁屏期间一律吞掉（不允许绕过）。
    return KeyEventResult.handled;
  }

  static int? _digitOf(LogicalKeyboardKey key) => switch (key) {
    LogicalKeyboardKey.digit0 || LogicalKeyboardKey.numpad0 => 0,
    LogicalKeyboardKey.digit1 || LogicalKeyboardKey.numpad1 => 1,
    LogicalKeyboardKey.digit2 || LogicalKeyboardKey.numpad2 => 2,
    LogicalKeyboardKey.digit3 || LogicalKeyboardKey.numpad3 => 3,
    LogicalKeyboardKey.digit4 || LogicalKeyboardKey.numpad4 => 4,
    LogicalKeyboardKey.digit5 || LogicalKeyboardKey.numpad5 => 5,
    LogicalKeyboardKey.digit6 || LogicalKeyboardKey.numpad6 => 6,
    LogicalKeyboardKey.digit7 || LogicalKeyboardKey.numpad7 => 7,
    LogicalKeyboardKey.digit8 || LogicalKeyboardKey.numpad8 => 8,
    LogicalKeyboardKey.digit9 || LogicalKeyboardKey.numpad9 => 9,
    _ => null,
  };

  void _selectByDigit(int digit) {
    // `1`~`9` → 第 1~9 项；`0` → 第 10 项。
    final int target = digit == 0 ? 9 : digit - 1;
    if (widget.questions.isEmpty) return;
    if (target < 0 || target >= _question.options.length) return;
    setState(() {
      _area = _QuizFocusArea.grid;
      _row = target ~/ _columns(_question.options);
      _col = target % _columns(_question.options);
      _toggle(target);
    });
  }

  void _move(LogicalKeyboardKey key) {
    if (widget.questions.isEmpty) return;
    final int cols = _columns(_question.options);
    final int rows = _rows;
    setState(() {
      _error = '';
      switch (key) {
        case LogicalKeyboardKey.arrowLeft:
          if (_area == _QuizFocusArea.grid) {
            _col = _col > 0 ? _col - 1 : 0;
          }
          break;
        case LogicalKeyboardKey.arrowRight:
          if (_area == _QuizFocusArea.grid) {
            final int lastCol = math.min(cols - 1, _lastColOfRow(_row, cols));
            _col = math.min(_col + 1, lastCol);
          }
          break;
        case LogicalKeyboardKey.arrowUp:
          if (_area == _QuizFocusArea.confirm) {
            _area = _QuizFocusArea.grid;
            _row = rows - 1;
            _col = math.min(_col, _lastColOfRow(_row, cols));
          } else if (_area == _QuizFocusArea.grid) {
            if (_row > 0) {
              _row -= 1;
              _col = math.min(_col, _lastColOfRow(_row, cols));
            } else {
              // 首行再往上 → 右上角「请求家长解锁」入口。
              _area = _QuizFocusArea.request;
            }
          } else if (_area == _QuizFocusArea.request) {
            // 顶部即止。
          }
          break;
        case LogicalKeyboardKey.arrowDown:
          if (_area == _QuizFocusArea.request) {
            _area = _QuizFocusArea.grid;
            _row = 0;
            _col = math.min(_col, _lastColOfRow(0, cols));
          } else if (_area == _QuizFocusArea.grid) {
            if (_row < rows - 1) {
              _row += 1;
              _col = math.min(_col, _lastColOfRow(_row, cols));
            } else {
              _area = _QuizFocusArea.confirm;
            }
          }
          break;
        default:
          break;
      }
    });
  }

  int _lastColOfRow(int row, int cols) {
    final int count = _question.options.length;
    return math.min(cols - 1, count - 1 - row * cols);
  }

  void _activate() {
    switch (_area) {
      case _QuizFocusArea.request:
        _requestParent();
        return;
      case _QuizFocusArea.confirm:
        unawaited(_submit());
        return;
      case _QuizFocusArea.grid:
        if (widget.questions.isEmpty) return;
        final int index = _row * _columns(_question.options) + _col;
        if (index < 0 || index >= _question.options.length) return;
        setState(() {
          _error = '';
          _toggle(index);
        });
        return;
    }
  }

  void _toggle(int index) {
    if (ParentalAttemptGate.instance.locked) return;
    if (!_question.multiple) {
      _selected
        ..clear()
        ..add(index);
      return;
    }
    if (!_selected.remove(index)) _selected.add(index);
  }

  Future<void> _submit() async {
    final ParentalQuizQuestion q = _question;
    final ParentalAttemptGate gate = ParentalAttemptGate.instance;
    if (gate.locked) return;
    if (q.multiple && _selected.isEmpty) return;
    final bool correct =
        _selected.length == q.answers.length &&
        _selected.every(q.answers.contains);
    if (correct) {
      await gate.recordSuccess();
      await widget.onSolved();
      return;
    }
    await gate.recordFailure();
    if (!mounted) return;
    setState(() {
      _error =
          '再想一想，还可以尝试 '
          '${ParentalAttemptGate.maxFailures - gate.failCount} 次';
      _index = widget.questions.isEmpty
          ? 0
          : (_index + 1) % widget.questions.length;
      _selected.clear();
      _area = _QuizFocusArea.grid;
      _row = 0;
      _col = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ParentalQuizQuestion q = _question;
    final List<ParentalQuizOption> options = q.options;
    final int cols = _columns(options);
    final int count = options.length;
    return Focus(
      focusNode: _focusNode,
      skipTraversal: true,
      onKeyEvent: _onKey,
      child: DecoratedBox(
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
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.2,
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints viewport) {
                final bool compact = viewport.maxHeight < 600;
                final double horizontalPadding = compact ? 24 : 40;
                final double verticalPadding = compact ? 14 : 22;
                final double gap = compact ? 8 : 12;
                return Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: horizontalPadding,
                    vertical: verticalPadding,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  '第 ${_index + 1} / ${widget.questions.length} 题'
                                  '${q.multiple ? ' · 多选' : ''}',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: Colors.white70,
                                  ),
                                ),
                                if (widget.header != null) ...<Widget>[
                                  const SizedBox(height: 4),
                                  widget.header!,
                                ],
                              ],
                            ),
                          ),
                          SizedBox(width: compact ? 10 : 16),
                          _RequestParentButton(
                            focused: _area == _QuizFocusArea.request,
                            compact: compact,
                            onTap: _requestParent,
                          ),
                        ],
                      ),
                      if (ParentalAttemptGate.instance.locked) ...<Widget>[
                        SizedBox(height: gap),
                        Text(
                          '先休息一下，'
                          '${ParentalAttemptGate.instance.remainingLockSec} 秒后再试',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: theme.colorScheme.error,
                            fontSize: 16,
                          ),
                        ),
                      ],
                      SizedBox(height: gap),
                      if (q.prompt.isNotEmpty)
                        Text(
                          q.prompt,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: compact ? 30 : 36,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      if (q.promptImageUrl.isNotEmpty) ...<Widget>[
                        SizedBox(height: gap),
                        Image.network(
                          q.promptImageUrl,
                          height: compact ? 68 : 100,
                          fit: BoxFit.contain,
                          errorBuilder:
                              (
                                BuildContext context,
                                Object error,
                                StackTrace? stack,
                              ) => const Icon(
                                Icons.broken_image_outlined,
                                color: Colors.white54,
                                size: 40,
                              ),
                        ),
                      ],
                      SizedBox(height: gap),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (BuildContext context, BoxConstraints c) {
                            final int rows = (count / cols).ceil().clamp(1, 10);
                            final double cellW =
                                (c.maxWidth - gap * (cols - 1)) / cols;
                            final double cellH =
                                (c.maxHeight - gap * (rows - 1)) / rows;
                            return GridView.count(
                              crossAxisCount: cols,
                              mainAxisSpacing: gap,
                              crossAxisSpacing: gap,
                              physics: const NeverScrollableScrollPhysics(),
                              childAspectRatio: cellW / math.max(cellH, 1),
                              children: <Widget>[
                                for (int i = 0; i < count; i++)
                                  _OptionCell(
                                    option: options[i],
                                    color: _palette[i % _palette.length]
                                        .withValues(
                                          alpha: 0.12 + (i % 3) * 0.03,
                                        ),
                                    focused:
                                        _area == _QuizFocusArea.grid &&
                                        _row * cols + _col == i,
                                    selected: _selected.contains(i),
                                    multiple: q.multiple,
                                    number: i + 1,
                                    onTap: () {
                                      setState(() {
                                        _area = _QuizFocusArea.grid;
                                        _row = i ~/ cols;
                                        _col = i % cols;
                                        _toggle(i);
                                      });
                                    },
                                  ),
                              ],
                            );
                          },
                        ),
                      ),
                      if (_error.isNotEmpty) ...<Widget>[
                        SizedBox(height: gap),
                        Text(
                          _error,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: theme.colorScheme.error,
                            fontSize: 16,
                          ),
                        ),
                      ],
                      SizedBox(height: gap),
                      Align(
                        alignment: Alignment.centerRight,
                        child: _ConfirmButton(
                          focused: _area == _QuizFocusArea.confirm,
                          enabled:
                              !ParentalAttemptGate.instance.locked &&
                              (!q.multiple || _selected.isNotEmpty),
                          compact: compact,
                          onTap: () => unawaited(_submit()),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// 右上角「请求家长解锁」入口（焦点态由本页自绘，不参与 Flutter 焦点遍历）。
class _RequestParentButton extends StatelessWidget {
  const _RequestParentButton({
    required this.focused,
    required this.compact,
    required this.onTap,
  });

  final bool focused;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return ExcludeFocus(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 14 : 18,
            vertical: compact ? 9 : 12,
          ),
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: focused ? 0.55 : 0.18),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: scheme.primary.withValues(alpha: focused ? 0.9 : 0.3),
              width: focused ? 2 : 1,
            ),
            boxShadow: focused
                ? <BoxShadow>[
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: 0.55),
                      blurRadius: 18,
                      spreadRadius: 2,
                    ),
                  ]
                : const <BoxShadow>[],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.mark_unread_chat_alt_outlined,
                size: 20,
                color: Colors.white,
              ),
              SizedBox(width: 8),
              Text(
                '请家长帮忙',
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 选项格：等宽等高，选中/聚焦用透明度与外发光区分。
class _OptionCell extends StatelessWidget {
  const _OptionCell({
    required this.option,
    required this.color,
    required this.focused,
    required this.selected,
    required this.multiple,
    required this.number,
    required this.onTap,
  });

  final ParentalQuizOption option;
  final Color color;
  final bool focused;
  final bool selected;
  final bool multiple;
  final int number;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color base = color.withValues(alpha: 1.0);
    return ExcludeFocus(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: base.withValues(alpha: focused || selected ? 0.55 : color.a),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: base.withValues(alpha: focused ? 0.95 : 0.30),
              width: focused ? 3 : 1.5,
            ),
            boxShadow: focused
                ? <BoxShadow>[
                    BoxShadow(
                      color: base.withValues(alpha: 0.55),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ]
                : const <BoxShadow>[],
          ),
          child: Stack(
            children: <Widget>[
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: option.image.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            ParentalQuizQuestion.resolveImageUrl(option.image),
                            fit: BoxFit.contain,
                            errorBuilder:
                                (
                                  BuildContext context,
                                  Object error,
                                  StackTrace? stack,
                                ) => const Icon(
                                  Icons.broken_image_outlined,
                                  color: Colors.white54,
                                  size: 32,
                                ),
                          ),
                        )
                      : Text(
                          option.text,
                          textAlign: TextAlign.center,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
              Positioned(
                left: 2,
                top: 0,
                child: Text(
                  '$number',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 14,
                  ),
                ),
              ),
              if (multiple)
                Positioned(
                  right: 0,
                  top: 0,
                  child: Icon(
                    selected ? Icons.check_box : Icons.check_box_outline_blank,
                    size: 18,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                )
              else if (selected)
                const Positioned(
                  right: 0,
                  top: 0,
                  child: Icon(
                    Icons.check_circle,
                    size: 18,
                    color: Colors.white,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 确认按钮：单选/多选都必须聚焦到这里按 OK 才判题。
class _ConfirmButton extends StatelessWidget {
  const _ConfirmButton({
    required this.focused,
    required this.enabled,
    required this.compact,
    required this.onTap,
  });

  final bool focused;
  final bool enabled;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return ExcludeFocus(
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 28 : 36,
            vertical: compact ? 10 : 14,
          ),
          decoration: BoxDecoration(
            color: scheme.primary.withValues(
              alpha: enabled ? (focused ? 0.75 : 0.35) : 0.12,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: scheme.primary.withValues(alpha: focused ? 0.95 : 0.3),
              width: focused ? 3 : 1.5,
            ),
            boxShadow: focused
                ? <BoxShadow>[
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: 0.55),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ]
                : const <BoxShadow>[],
          ),
          child: Text(
            '确认答案',
            style: TextStyle(
              color: enabled ? Colors.white : Colors.white38,
              fontSize: 22,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
