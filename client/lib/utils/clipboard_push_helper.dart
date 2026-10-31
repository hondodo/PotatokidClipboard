import 'dart:async';

import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:potatokid_clipboard/framework/utils/app_log.dart';
import 'package:potatokid_clipboard/pages/home/tabs/clipboard/repository/clipboard_repository.dart';
import 'package:potatokid_clipboard/utils/error_utils.dart';

class ClipBoardPushHelper {
  String _lastClipboardText = '';
  String get lastClipboardText => _lastClipboardText;

  ClipBoardPushHelper() {
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

  /// 检查剪贴板内容
  Future<void> checkClipboard() async {
    try {
      final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
      if (data != null && data.text != null) {
        String text = data.text!;
        if (text.isNotEmpty && _lastClipboardText != text) {
          _handleClipboardChange(text);
        }
      }
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

    Get.find<ClipboardRepository>().setClipboard(text).catchError((e) {
      Log.e('ClipboardService] 保存剪贴板内容失败: $e');
      ErrorUtils.showErrorToast(e);
    });
  }
}
