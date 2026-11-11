import 'dart:async';
import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

typedef AppExitCleanup = Future<void> Function();

/// 统一协调“停止媒体 → 退出应用”，供手动退出与定时退出共用。
class AppExitController {
  AppExitController._();

  static final AppExitController instance = AppExitController._();

  static const MethodChannel _appChannel = MethodChannel('potatokid/app');
  static const Duration _cleanupTimeout = Duration(seconds: 1);

  AppExitCleanup? _playbackCleanup;
  Future<void>? _exitFuture;

  void attachPlaybackCleanup(AppExitCleanup cleanup) {
    _playbackCleanup = cleanup;
  }

  void detachPlaybackCleanup() {
    _playbackCleanup = null;
  }

  /// 多个退出来源同时触发时只执行一次。
  Future<void> exit() => _exitFuture ??= _exit();

  Future<void> _exit() async {
    final AppExitCleanup? cleanup = _playbackCleanup;
    if (cleanup != null) {
      try {
        await cleanup().timeout(_cleanupTimeout);
      } catch (_) {
        // 播放器清理失败或超时不能阻止用户退出。
      }
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        await _appChannel.invokeMethod<void>('exitApp');
        return;
      } catch (_) {
        // 原生通道不可用时至少结束当前 Activity。
        await SystemNavigator.pop();
        return;
      }
    }

    // Windows 的 SystemNavigator.pop() 不退出窗口；桌面端直接正常结束进程。
    io.exit(0);
  }
}
