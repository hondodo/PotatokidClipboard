import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:potatokid_clipboard/framework/utils/app_log.dart';
import 'package:potatokid_clipboard/pages/home/tabs/clipboard/repository/clipboard_repository.dart';
import 'package:potatokid_clipboard/services/settings_service.dart';
import 'package:potatokid_clipboard/user/user_service.dart';
import 'package:potatokid_clipboard/utils/clipboard_utils.dart';
import 'package:potatokid_clipboard/utils/device_utils.dart';
import 'package:potatokid_clipboard/utils/error_utils.dart';

class ClipboardService extends GetxService {
  StreamController<String> clipboardTextStreamController =
      StreamController<String>.broadcast();
  Stream<String> get clipboardTextStream =>
      clipboardTextStreamController.stream;

  /// 最近一次实际从系统剪贴板读到的值（变化检测以此为准，而非"意向值"，
  /// 避免写入系统剪贴板尚未生效/被系统归一化时，轮询把旧值误判为新复制）
  String _lastObservedText = '';

  /// 最近一次由本 App 写入系统剪贴板的内容与时间，用于识别自己写入的回声
  String? _lastLocalWriteText;
  DateTime? _lastLocalWriteAt;

  /// 回声抑制窗口：写入系统剪贴板后的一段时间内，读回内容与写入内容
  /// 归一化后一致的，视为自己的回声，不再上传
  static const Duration _echoSuppressWindow = Duration(seconds: 10);

  Timer? _pollingTimer;
  bool _isMonitoring = false;

  ClipboardService() {
    syncClipboardNotPostToServer();
  }

  /// 统一换行符，消除 Windows(\r\n) 与 Linux/Android(\n) 之间的回声差异
  static String normalizeLineEndings(String text) =>
      text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

  Future syncClipboardNotPostToServer() async {
    return Clipboard.getData(Clipboard.kTextPlain).then((value) {
      if (value != null && value.text != null) {
        String text = value.text!;
        if (text.isNotEmpty) {
          // 首次进入时，记录剪贴板内容，不触发监听，只有打开app后，剪贴板有内容变化时，才会触发监听，避免重复触发监听
          _lastObservedText = text;
        }
      }
    }).catchError((e) {
      Log.e('ClipboardService] 获取剪贴板内容失败: $e');
    });
  }

  /// 设置当前剪贴板内容，为避免点击app里的复制按钮，触发监听，导致重复保存
  void setCurrentClipboard(String text) {
    if (text.isEmpty) {
      return;
    }
    // 只记录写入意图，不更新 _lastObservedText：
    // 系统剪贴板的实际值由轮询读回确认，写入未生效期间不会产生误判
    _lastLocalWriteText = text;
    _lastLocalWriteAt = DateTime.now();
    unawaited(ClipboardUtils.setText(text));
  }

  /// 读回内容是否为本 App 刚写入剪贴板的回声（含系统归一化差异，如 \r\n -> \n）
  bool _isSelfEcho(String text) {
    final written = _lastLocalWriteText;
    final writtenAt = _lastLocalWriteAt;
    if (written == null || writtenAt == null) {
      return false;
    }
    if (DateTime.now().difference(writtenAt) > _echoSuppressWindow) {
      return false;
    }
    return normalizeLineEndings(text) == normalizeLineEndings(written);
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
        if (text.isNotEmpty && _lastObservedText != text) {
          // 以实际读回值为准更新基准，之后相同内容不会再被判定为变化
          _lastObservedText = text;
          // 自己刚写入剪贴板的内容（含系统归一化差异）不视为新复制，避免回声上传
          if (_isSelfEcho(text)) {
            return;
          }
          // 如果是ios，那么要设置剪贴板内容，否则会一直提示获取剪贴板的来源
          if (DeviceUtils.instance.isMobile()) {
            await ClipboardUtils.setText(text);
          }
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
    Get.find<SettingsService>().isUploadingClipboardFailed.value = false;
    Get.find<ClipboardRepository>().setClipboard(text).catchError((e) {
      Log.e('ClipboardService] 保存剪贴板内容失败: $e');
      ErrorUtils.showErrorToast(e);
      Get.find<SettingsService>().isUploadingClipboardFailed.value = true;
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

  String get lastClipboardText => _lastObservedText;
}
