// ignore_for_file: constant_identifier_names

import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:potatokid_clipboard/framework/components/loading_content_widget.dart';
import 'package:potatokid_clipboard/utils/string_utils.dart';

Function emptyFun() {
  return () {};
}

class DialogHelper {
  static const String COMMONTTAG = 'common'; // 公共tag

  static Future<void> dismiss({String? tag, dynamic result}) {
    return SmartDialog.dismiss(tag: tag, result: result);
  }

  // MARK: - 自定义文案loading, 默认带loading文案
  static Future<void> showTextLoading({
    String text = '',
    VoidCallback onDismiss = emptyFun,
    bool backDismiss = false,
  }) {
    SmartDialog.showLoading(
      builder: (_) => LoadingWidget(text: text),
      onDismiss: onDismiss,
      backType: backDismiss ? SmartBackType.block : SmartBackType.normal,
    );
    return Future.value();
  }

  // MARK: - 只会生成一个loading对象keepSingle属性为true
  static Future<void> showSingleLoading(
      {String text = '',
      VoidCallback onDismiss = emptyFun,
      VoidCallback cancelPress = emptyFun,
      bool keepSingle = true,
      bool useAnimation = false,
      bool clickMaskDismiss = false,
      bool backDismiss = false,
      String tag = COMMONTTAG}) {
    SmartDialog.show(
      tag: COMMONTTAG,
      backType: backDismiss ? SmartBackType.block : SmartBackType.normal,
      useAnimation: useAnimation,
      keepSingle: keepSingle,
      builder: (_) => LoadingWidget(text: text),
      onDismiss: onDismiss,
      clickMaskDismiss: clickMaskDismiss,
    );
    return Future.value();
  }

  static Future<void> showTextToast(
    String text, {
    Alignment alignment = Alignment.center,
    bool usePenetrate = true,
    VoidCallback onDismiss = emptyFun,
    Duration? displayTime,
    bool isCanBack = true,
    String? dismissTag = 'common',
  }) {
    if (Get.context == null) {
      // 如果context为空，则不显示toast，此时还没初始化完成，避免报错
      return Future.value(null);
    }
    return isCanBack
        ? SmartDialog.dismiss(tag: dismissTag).then((_) {
            Future.delayed(const Duration(milliseconds: 300), () {
              SmartDialog.showToast(text,
                  displayTime: displayTime,
                  usePenetrate: usePenetrate,
                  alignment: alignment,
                  onDismiss: onDismiss,
                  maskColor: usePenetrate == false
                      ? Colors.transparent
                      : Colors.black.withOpacity(0.4));
            });
          })
        : SmartDialog.dismiss(tag: dismissTag).then((_) {
            Future.delayed(const Duration(milliseconds: 300), () {
              SmartDialog.show(
                tag: dismissTag,
                backType: SmartBackType.normal,
                alignment: Alignment.center,
                displayTime: const Duration(milliseconds: 2000),
                onDismiss: onDismiss,
                clickMaskDismiss: false,
                usePenetrate: usePenetrate,
                maskColor: usePenetrate == false
                    ? Colors.transparent
                    : Colors.black.withOpacity(0.4),
                builder: (context) {
                  return Container(
                    padding: const EdgeInsets.only(top: 10, bottom: 10),
                    width: StringUtils.getTextWidth(
                            text,
                            const TextStyle(
                              fontSize: 14,
                              color: Colors.white,
                            )) +
                        40,
                    decoration: BoxDecoration(
                      color: const Color(0xFF3B3B70),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Container(
                      margin: const EdgeInsets.only(top: 6),
                      child: Text(
                        textAlign: TextAlign.center,
                        text,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  );
                },
              );
            });
          });
  }
}
