import 'package:flutter/material.dart';
import 'package:pscreen_screen/features/msg/protocol/envelope_builder.dart';

/// 数字键直选频道（家长端遥控面板，3×4 网格）。
///
/// 方案 A「电视端收口」：每按一位数字**立即**发一条 `channel_digit {digit}`，
/// 手机端只做本地回显、不在本机计时；2 秒缓冲、超范围判断、跳台结算全部
/// 交给电视端同一个 `ChannelNumberInputController`。因此手机与电视屏回显的
/// 是同一份状态，与人在电视上按数字键是同一套逻辑。
///
/// 键位：`1 2 3 / 4 5 6 / 7 8 9 / 0 + 立即跳台（占两格）`。
/// 没有「清除」键——与真实遥控一致（输错等 2 秒自动结算/超范围提示；
/// 也可重新进遥控页清空）。「立即跳台」不等 2 秒，下发 `channel_digit_resolve`
/// 让电视端按当前缓冲立即结算。
class ChannelNumberPad extends StatefulWidget {
  const ChannelNumberPad({
    super.key,
    required this.onCommand,
    required this.enabled,
    this.onHint,
  });

  /// 发送已构造好的命令信封（发到当前这台被控电视）。
  final ValueChanged<String> onCommand;

  /// 设备在线才可点；离线时整块置灰。
  final bool enabled;

  /// 轻提示（回显「已发 N」/「请先输入频道号」）。
  final void Function(String message, {bool error})? onHint;

  @override
  State<ChannelNumberPad> createState() => _ChannelNumberPadState();
}

class _ChannelNumberPadState extends State<ChannelNumberPad> {
  /// 手机本地回显的频道号串（最多 3 位，与电视端 count 上限同数量级）。
  /// 只回显不计时——结算权在电视端。
  String _digits = '';

  bool get _hasDigits => _digits.isNotEmpty;

  void _inputDigit(int digit) {
    if (_digits.length >= 3) return;
    setState(() => _digits = '$_digits$digit');
    widget.onCommand(
      buildCommandEnvelope('channel_digit', <String, dynamic>{'digit': digit}),
    );
    widget.onHint?.call(
      '已发 $digit → 电视端输入 $_digits（停 2 秒自动结算，以电视屏为准）',
    );
  }

  void _resolveNow() {
    if (!_hasDigits) {
      widget.onHint?.call('请先输入频道号', error: true);
      return;
    }
    widget.onCommand(buildCommandEnvelope('channel_digit_resolve'));
    widget.onHint?.call('已让电视端立即结算 $_digits（范围以电视为准）');
    setState(() => _digits = '');
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
        const SizedBox(height: 10),
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
          '每按一位立即发到电视，电视屏同步回显；停 2 秒自动跳台，或点「立即跳台」。'
          '范围 / 超范围以电视屏为准。',
          style: TextStyle(color: cs.outline, fontSize: 12),
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
