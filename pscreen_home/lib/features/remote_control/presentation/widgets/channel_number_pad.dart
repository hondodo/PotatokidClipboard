import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pscreen_screen/features/msg/protocol/envelope_builder.dart';

/// 数字键直选频道（家长端遥控面板，3×4 网格）。
///
/// 方案 A「电视端收口」：每按一位数字**立即**发一条 `channel_digit {digit}`，
/// 跳台 / 超范围 / 2 秒结算全部由电视端同一个 `ChannelNumberInputController`
/// 完成——与人在电视上按数字键是同一套逻辑。
///
/// 手机端**只回显、不判范围、不下发跳台命令**；本机另起一个 2 秒计时器，
/// 但只用于**清空本地回显**（纯 UI，不参与跳台）。否则按满 3 位后回显会一直
/// 卡住、后续按键全被 `length >= 3` 拒绝（真机实测：输 121 后停 2 秒电视已
/// 跳台，手机却停在 121，之后全失败）。这个计时器只管输入框，结算权始终在
/// 电视端；两端计时起点差一个网络往返，用户无感。
///
/// 键位：`1 2 3 / 4 5 6 / 7 8 9 / 0 + 立即跳台（占两格）`。没有「清除」键。
/// 提示走键盘内一行小字（Key: `channel-number-hint`），不再用 SnackBar
/// 抢用户观察焦点。
class ChannelNumberPad extends StatefulWidget {
  const ChannelNumberPad({
    super.key,
    required this.onCommand,
    required this.enabled,
  });

  /// 发送已构造好的命令信封（发到当前这台被控电视）。
  final ValueChanged<String> onCommand;

  /// 设备在线才可点；离线时整块置灰。
  final bool enabled;

  @override
  State<ChannelNumberPad> createState() => _ChannelNumberPadState();
}

class _ChannelNumberPadState extends State<ChannelNumberPad> {
  static const int _maxDigits = 3;
  static const Duration _displayTtl = Duration(seconds: 2);
  static const String _idleHint = '依次按 0–9，停 2 秒电视自动跳台';

  /// 手机本地回显的频道号串（最多 3 位）。
  String _digits = '';

  /// 键盘内的轻提示；null 时显示 [_idleHint]。不弹 SnackBar。
  String? _hint;
  bool _hintIsError = false;

  /// 仅用于清空本地回显的计时器——不参与跳台/范围判断（结算权在电视端）。
  Timer? _displayTimer;

  bool get _hasDigits => _digits.isNotEmpty;

  void _inputDigit(int digit) {
    if (_digits.length >= _maxDigits) return;
    setState(() {
      _digits = '$_digits$digit';
      _hint = '已发 $digit · 共 $_digits，电视停 2 秒自动结算';
      _hintIsError = false;
    });
    widget.onCommand(
      buildCommandEnvelope('channel_digit', <String, dynamic>{'digit': digit}),
    );
    // 每次有效输入重置「清回显」计时；满 3 位后它仍会到点清空，解除 length 上限锁定。
    _displayTimer?.cancel();
    _displayTimer = Timer(_displayTtl, _resetDisplay);
  }

  void _resolveNow() {
    if (!_hasDigits) {
      setState(() {
        _hint = '请先输入频道号';
        _hintIsError = true;
      });
      return;
    }
    widget.onCommand(buildCommandEnvelope('channel_digit_resolve'));
    _displayTimer?.cancel();
    _resetDisplay();
  }

  void _resetDisplay() {
    if (!mounted) return;
    setState(() {
      _digits = '';
      _hint = null;
      _hintIsError = false;
    });
  }

  @override
  void dispose() {
    _displayTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(Icons.numbers, size: 18, color: cs.primary),
            const SizedBox(width: 8),
            Text('数字键直选频道', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(width: 8),
            _digits.isEmpty
                ? Text('输入频道号',
                    key: const Key('channel-number-display'),
                    style: TextStyle(color: cs.outline, fontSize: 13))
                : Text(
                    _digits,
                    key: const Key('channel-number-display'),
                    style: TextStyle(
                      color: cs.primary,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 4,
                    ),
                  ),
          ],
        ),
        const SizedBox(height: 6),
        // 轻提示走键盘内一行小字，不再弹 SnackBar 抢焦点。
        Text(
          _hint ?? _idleHint,
          key: const Key('channel-number-hint'),
          style: TextStyle(
            color: _hintIsError ? cs.error : (_hint == null ? cs.outline : cs.primary),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 8),
        // 3×4 网格用 Row + Expanded(flex) 实现，最后一行「立即跳台」占两格。
        _KeyRow(keys: const <int>[1, 2, 3], enabled: widget.enabled, onDigit: _inputDigit),
        _KeyRow(keys: const <int>[4, 5, 6], enabled: widget.enabled, onDigit: _inputDigit),
        _KeyRow(keys: const <int>[7, 8, 9], enabled: widget.enabled, onDigit: _inputDigit),
        Row(
          children: <Widget>[
            Expanded(
              flex: 1,
              child: _DigitKey(
                key: const Key('digit-0'),
                label: '0',
                onTap: widget.enabled ? () => _inputDigit(0) : null,
              ),
            ),
            const SizedBox(width: 8),
            // 占两格：空缓冲时仍可点，点击给「请先输入频道号」提示。
            Expanded(
              flex: 2,
              child: _DigitKey(
                label: '立即跳台',
                emphasized: true,
                onTap: widget.enabled ? _resolveNow : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '数字键与电视本机一致；超范围 / 当前频道以电视屏为准。',
          style: TextStyle(color: cs.outline, fontSize: 11),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// 一行三个数字键，等宽伸展。
class _KeyRow extends StatelessWidget {
  const _KeyRow({
    required this.keys,
    required this.enabled,
    required this.onDigit,
  });

  final List<int> keys;
  final bool enabled;
  final ValueChanged<int> onDigit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: <Widget>[
          for (final int d in keys) ...<Widget>[
            Expanded(
              child: _DigitKey(
                key: ValueKey<String>('digit-$d'),
                label: '$d',
                onTap: enabled ? () => onDigit(d) : null,
              ),
            ),
            if (d != keys.last) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _DigitKey extends StatelessWidget {
  const _DigitKey({
    super.key,
    required this.label,
    required this.onTap,
    this.emphasized = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: OutlinedButton(
        onPressed: onTap,
        style: emphasized
            ? OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                backgroundColor: Theme.of(context).colorScheme.primary,
              )
            : null,
        child: Text(
          label,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
