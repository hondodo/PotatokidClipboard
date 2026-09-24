import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

mixin class TipOverlayMixin {
  OverlayEntry? _overlayEntry;
  Timer? _clearTipTimer;

  void showError(String message) {
    if (Get.context != null) {
      ScaffoldMessenger.of(Get.context!).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    }
  }

  void showSuccess(String message, {int timeout = 2000}) {
    if (Get.context != null) {
      ScaffoldMessenger.of(Get.context!).showSnackBar(
        SnackBar(
            content: Text(message),
            backgroundColor: Colors.green,
            duration: Duration(milliseconds: timeout)),
      );
    }
  }

  void showTip(String message, {int timeout = 2000}) {
    if (Get.context != null) {
      // 使用Overlay显示自定义提示
      _showCustomTip(message, timeout: timeout);
    }
  }

  void _showCustomTip(String message, {int timeout = 2000}) {
    // 移除之前的提示
    _removeCustomTip();

    // 计算最大宽度
    final screenWidth = MediaQuery.of(Get.context!).size.width;
    final maxWidth = (screenWidth * 0.5).clamp(0.0, 500.0);

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: 80,
        left: 0,
        right: 0,
        child: Center(
          child: AnimatedOpacity(
            opacity: 1,
            duration: const Duration(milliseconds: 300),
            child: Container(
              constraints: BoxConstraints(
                maxWidth: maxWidth,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.blue,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  decoration: TextDecoration.none, // 明确禁用装饰
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );

    Overlay.of(Get.context!).insert(_overlayEntry!);

    // 2秒后自动移除
    _clearTipTimer?.cancel();
    _clearTipTimer = Timer(Duration(milliseconds: timeout), () {
      _removeCustomTip();
    });
  }

  void _removeCustomTip() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }
}
