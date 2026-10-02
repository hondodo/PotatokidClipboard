import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:potatokid_screen/features/iptv/application/live_channel_controller.dart';

/// 首页「数字键直选频道」控制器（全局单例）。
///
/// 遥控器按数字键（0~9）时把数字累积到缓冲区并回显，让用户看清自己按到第几位；
/// [inputInterval] 内没有新的数字就按当前缓冲区结算：
/// - 号码落在 `1..频道总数` 内 → 切到该频道（序号从 1 开始，与频道条显示一致）；
/// - 号码超出范围 → 置 [outOfRange] 提示态，[outOfRangeDuration] 后自动清除；
/// - 号码已经不可能落进范围（继续追加数字只会更大）→ 立即结算，不必等满 [inputInterval]。
class ChannelNumberInputController extends ChangeNotifier {
  ChannelNumberInputController._();

  /// 全局单例。
  static final ChannelNumberInputController instance = ChannelNumberInputController._();

  /// 两次数字输入之间的等待时间：超过即按当前缓冲区结算。
  static const Duration inputInterval = Duration(seconds: 2);

  /// 「超出范围」提示的显示时长。
  static const Duration outOfRangeDuration = Duration(seconds: 2);

  String _digits = '';
  bool _outOfRange = false;
  Timer? _resolveTimer;
  Timer? _outOfRangeTimer;

  /// 已输入的数字串（回显用，形如 `1` / `12` / `123`）。
  String get digits => _digits;

  /// 当前是否在提示「频道号超出范围」。
  bool get outOfRange => _outOfRange;

  /// 是否有内容需要回显（数字或超出范围提示）。
  bool get visible => _digits.isNotEmpty || _outOfRange;

  /// 输入一位数字（0~9）。
  void input(int digit) {
    final int count = LiveChannelController.instance.count;
    if (count <= 0) return;
    _outOfRangeTimer?.cancel();
    _outOfRange = false;
    _digits = '$_digits$digit';
    // 追加数字只会让号码变大：一旦超过总数就不可能再命中，立即提示，不用等满 2 秒。
    if ((int.tryParse(_digits) ?? 0) > count) {
      _showOutOfRange();
      return;
    }
    _resolveTimer?.cancel();
    _resolveTimer = Timer(inputInterval, _resolve);
    notifyListeners();
  }

  /// 按当前缓冲区结算：命中就切台，否则提示超出范围。
  void _resolve() {
    _resolveTimer = null;
    final int count = LiveChannelController.instance.count;
    final int value = int.tryParse(_digits) ?? 0;
    _digits = '';
    if (value < 1 || value > count) {
      _showOutOfRange();
      return;
    }
    notifyListeners();
    LiveChannelController.instance.select(value - 1);
  }

  /// 清空缓冲区并显示「超出范围」提示。
  void _showOutOfRange() {
    _resolveTimer?.cancel();
    _resolveTimer = null;
    _digits = '';
    _outOfRange = true;
    notifyListeners();
    _outOfRangeTimer?.cancel();
    _outOfRangeTimer = Timer(outOfRangeDuration, () {
      _outOfRange = false;
      notifyListeners();
    });
  }
}