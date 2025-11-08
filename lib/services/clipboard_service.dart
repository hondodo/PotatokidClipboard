import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:potatokid_clipboard/framework/utils/app_log.dart';
import 'package:potatokid_clipboard/pages/home/tabs/clipboard/repository/clipboard_repository.dart';
import 'package:potatokid_clipboard/services/settings_service.dart';
import 'package:potatokid_clipboard/user/user_service.dart';
import 'package:potatokid_clipboard/utils/error_utils.dart';

class ClipboardService extends GetxService {
  StreamController<String> clipboardTextStreamController =
      StreamController<String>.broadcast();
  Stream<String> get clipboardTextStream =>
      clipboardTextStreamController.stream;

  String _lastClipboardText = '';
  Timer? _pollingTimer;
  bool _isMonitoring = false;

  ClipboardService() {
    syncClipboardNotPostToServer();
  }

  Future syncClipboardNotPostToServer() async {
    return Clipboard.getData(Clipboard.kTextPlain).then((value) {
      if (value != null && value.text != null) {
        String text = value.text!;
        if (text.isNotEmpty && _lastClipboardText != text) {
          // 首次进入时，设置剪贴板内容，不触发监听，只有打开app后，剪贴板有内容变化时，才会触发监听，避免重复触发监听
          _lastClipboardText = text;
        }
      }
    }).catchError((e) {
      Log.e('ClipboardService] 获取剪贴板内容失败: $e');
    });
  }

  /// 设置当前剪贴板内容，为避免点击app里的复制按钮，触发监听，导致重复保存
  void setCurrentClipboard(String text) {
    _lastClipboardText = text;
    if (text.isEmpty) {
      return;
    }
    Clipboard.setData(ClipboardData(text: text));
  }

  /// 启动监控
  /// 使用 Flutter 自带的 Clipboard API，通过轮询机制监控剪贴板变化
  void startMonitoring() {
    if (_isMonitoring) {
      Log.w('ClipboardService] 监控已经启动');
      return;
    }

    _isMonitoring = true;
    Log.d('ClipboardService] 启动剪贴板监控（使用轮询机制）');
    syncClipboardNotPostToServer();
    _startPolling();
  }

  /// 停止监控
  void stopMonitoring() {
    if (!_isMonitoring) {
      return;
    }

    _isMonitoring = false;
    _stopPolling();
    Log.d('ClipboardService] 剪贴板监控已停止');
  }

  /// 启动轮询机制
  void _startPolling() {
    // 立即检查一次
    _checkClipboard();

    // 每 500ms 轮询一次
    _pollingTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      _checkClipboard();
    });

    Log.d('ClipboardService] 轮询机制已启动，间隔: 500ms');
  }

  /// 停止轮询
  void _stopPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    Log.d('ClipboardService] 轮询机制已停止');
  }

  /// 检查剪贴板内容
  Future<void> _checkClipboard() async {
    try {
      // 系统限制，只有在应用处于前台时才能访问剪贴板；如果处于后台，剪贴板返回内容为null(Android 10+)
      // if(AppLifecyclesStateService.currentState != AppLifecycleState.resumed){
      // if(Platform.isAndroid){
      //   // 系统
      //   return;
      // }
      // }
      final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
      if (data != null && data.text != null) {
        String text = data.text!;
        if (text.isNotEmpty && _lastClipboardText != text) {
          _handleClipboardChange(text);
        }
      } else {}
    } catch (e) {
      // 忽略轮询时的错误，避免日志过多
      // Log.e('ClipboardService] 轮询检查剪贴板失败: $e');
    }
  }

  /// 处理剪贴板变化
  void _handleClipboardChange(String text) {
    Log.d(
        'ClipboardService] 剪贴板内容变化: ${text.length > 50 ? "${text.substring(0, 50)}..." : text}');
    _lastClipboardText = text;

    if (clipboardTextStreamController.isClosed) {
      Log.w('ClipboardService] StreamController 已关闭，无法发送数据');
      return;
    }

    clipboardTextStreamController.add(text);

    if (!Get.find<UserService>().hasLogin) {
      debugPrint('ClipboardService] 未登录，不保存剪贴板内容');
      return;
    }
    Get.find<SettingsService>().isUploadingClipboard.value = true;
    Get.find<ClipboardRepository>().setClipboard(text).catchError((e) {
      Log.e('ClipboardService] 保存剪贴板内容失败: $e');
      ErrorUtils.showErrorToast(e);
    }).whenComplete(() {
      Get.find<SettingsService>().isUploadingClipboard.value = false;
    });
  }

  @override
  void onClose() {
    stopMonitoring();
    clipboardTextStreamController.close();
    super.onClose();
  }

  String get lastClipboardText => _lastClipboardText;
}
