import 'dart:async';
import 'dart:io';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:potatokid_clipboard/framework/utils/app_log.dart';

class BatteryController extends GetxController {
  final Battery _battery = Battery();
  static const MethodChannel _batteryChannel =
      MethodChannel('dev.fluttercommunity.plus/battery');
  final Rx<BatteryState?> batteryState = Rx<BatteryState?>(null);
  final Rx<int?> batteryLevel = Rx<int?>(null);
  StreamSubscription<BatteryState>? _batteryStateSubscription;
  Timer? _batteryLevelTimer;
  bool _hasClosed = false;

  @override
  void onInit() {
    super.onInit();
    unawaited(_refreshBatteryState());
    _batteryStateSubscription = _battery.onBatteryStateChanged.listen(
      _updateBatteryState,
      onError: (Object error) {
        Log.e('BatteryController] 监听电池状态失败: $error');
      },
    );
    unawaited(_refreshBatteryLevel());
  }

  @override
  void onClose() {
    _hasClosed = true;
    if (_batteryStateSubscription != null) {
      _batteryStateSubscription!.cancel();
    }
    stopTimer();
    super.onClose();
  }

  void stopTimer() {
    _batteryLevelTimer?.cancel();
    _batteryLevelTimer = null;
  }

  void startTimer({Duration delay = const Duration(seconds: 1)}) {
    stopTimer();
    _batteryLevelTimer = Timer(delay, onTimerTick);
  }

  void onTimerTick() {
    stopTimer();
    if (_hasClosed) return;
    unawaited(_refreshBatteryLevel());
  }

  Future<void> _refreshBatteryState() async {
    try {
      final state = await _battery.batteryState;
      if (!_hasClosed) _updateBatteryState(state);
    } catch (error) {
      Log.e('BatteryController] 获取电池状态失败: $error');
    }
  }

  Future<void> _refreshBatteryLevel() async {
    int? level;
    try {
      if (Platform.isMacOS) {
        // battery_plus 在 macOS 无电池时返回字符串 UNAVAILABLE，
        // 不能通过插件的 int 类型接口读取。
        final value = await _batteryChannel.invokeMethod<Object?>(
          'getBatteryLevel',
        );
        if (value is int) level = value;
      } else {
        level = await _battery.batteryLevel;
      }
      if (level != null && (level < 0 || level > 100)) level = null;
    } catch (error) {
      Log.e('BatteryController] 获取电量失败: $error');
    }
    if (_hasClosed) return;
    _updateBatteryLevel(level);
    startTimer(
      delay: level == null
          ? const Duration(seconds: 30)
          : const Duration(seconds: 1),
    );
  }

  void _updateBatteryState(BatteryState state) {
    if (batteryState.value == state) return;
    batteryState.value = state;
  }

  void _updateBatteryLevel(int? level) {
    if (batteryLevel.value == level) return;
    batteryLevel.value = level;
  }
}

extension BatteryStateExtension on BatteryState {
  String get text {
    switch (this) {
      case BatteryState.full:
        return '满电'.tr;
      case BatteryState.charging:
        return '充电中'.tr;
      case BatteryState.connectedNotCharging:
        return '连接中'.tr;
      case BatteryState.discharging:
        return '放电中'.tr;
      case BatteryState.unknown:
        return '未知'.tr;
    }
  }

  IconData get icon {
    switch (this) {
      case BatteryState.full:
        return Icons.battery_full;
      case BatteryState.charging:
        return Icons.battery_charging_full;
      case BatteryState.connectedNotCharging:
        return Icons.battery_charging_full;
      case BatteryState.discharging:
        return Icons.battery_charging_full;
      case BatteryState.unknown:
        return Icons.battery_unknown;
    }
  }
}
