import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class BatteryController extends GetxController {
  final Battery _battery = Battery();
  final Rx<BatteryState?> batteryState = Rx<BatteryState?>(null);
  final Rx<int> batteryLevel = Rx<int>(0);
  StreamSubscription<BatteryState>? _batteryStateSubscription;
  Timer? _batteryLevelTimer;
  bool _hasClosed = false;

  @override
  void onInit() {
    super.onInit();
    _battery.batteryState.then(_updateBatteryState);
    _battery.batteryLevel.then(_updateBatteryLevel);
    _batteryStateSubscription =
        _battery.onBatteryStateChanged.listen(_updateBatteryState);
    startTimer();
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

  void startTimer() {
    stopTimer();
    _batteryLevelTimer = Timer(const Duration(milliseconds: 1000), onTimerTick);
  }

  void onTimerTick() {
    stopTimer();
    if (_hasClosed) return;
    _battery.batteryLevel.then((level) {
      if (_hasClosed) return;
      _updateBatteryLevel(level);
      startTimer();
    });
  }

  void _updateBatteryState(BatteryState state) {
    if (batteryState.value == state) return;
    batteryState.value = state;
  }

  void _updateBatteryLevel(int level) {
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
