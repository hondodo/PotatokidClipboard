import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:potatokid_clipboard/framework/base/base_get_vm.dart';
import 'package:potatokid_clipboard/framework/utils/app_log.dart';
import 'package:potatokid_clipboard/pages/home/tabs/clipboard/model/clipboard_item_model.dart';
import 'package:potatokid_clipboard/pages/home/tabs/clipboard/repository/clipboard_repository.dart';
import 'package:potatokid_clipboard/services/app_lifecycles_state_service.dart';
import 'package:potatokid_clipboard/services/clipboard_service.dart';
import 'package:potatokid_clipboard/services/settings_service.dart';
import 'package:potatokid_clipboard/user/model/user_model.dart';
import 'package:potatokid_clipboard/user/user_service.dart';
import 'package:potatokid_clipboard/utils/error_utils.dart';

class ClipboardController extends BaseGetVM {
  final TextEditingController textController = TextEditingController();

  /// 定时器，用于定时获取剪贴板列表，每秒获取一次
  Timer? _clipboardListTimer;

  /// 剪贴板最大id
  int _maxClipboardId = 0;

  final RxList<ClipboardItemModel> clipboardList = <ClipboardItemModel>[].obs;

  Rx<UserModel> get user => Get.find<UserService>().user;

  @override
  void onInit() {
    super.onInit();
    user.listen(onUserChanged);
    onTimerTick();
  }

  Future<void> onLoadClipboard() async {
    var response = await Get.find<ClipboardRepository>()
        .getClipboardList(fromId: _maxClipboardId);
    if (response.clipboards != null && response.clipboards!.isNotEmpty) {
      for (var item in response.clipboards!) {
        if (item.id > _maxClipboardId) {
          _maxClipboardId = item.id;
        }
      }
      // 添加到列表
      clipboardList.addAll(response.clipboards!);
      // 排序,按id降序
      clipboardList.sort((a, b) => b.id.compareTo(a.id));
      // 如果超过100条，则删除最早的一条
      while (clipboardList.length > 100) {
        clipboardList.removeLast();
      }
    }
    debugPrint(
        'ClipboardController] 获取剪贴板列表成功，起始id: $_maxClipboardId, 列表长度: ${response.clipboards?.length}');
  }

  Future<void> onSetClipboard() async {
    try {
      await Get.find<ClipboardRepository>().setClipboard(textController.text);
      Get.find<ClipboardService>().setCurrentClipboard(textController.text);
      textController.clear();
    } catch (e) {
      ErrorUtils.showErrorToast(e);
    }
  }

  void onTimerTick() {
    _clipboardListTimer?.cancel();
    _clipboardListTimer = null;
    int autoCheckClipboardIntervalS =
        Get.find<SettingsService>().autoCheckClipboardIntervalS.value;
    if (autoCheckClipboardIntervalS <
            SettingsService.MIN_AUTO_CHECK_CLIPBOARD_INTERVAL_S ||
        autoCheckClipboardIntervalS >
            SettingsService.MAX_AUTO_CHECK_CLIPBOARD_INTERVAL_S) {
      autoCheckClipboardIntervalS =
          SettingsService.DEFAULT_AUTO_CHECK_CLIPBOARD_INTERVAL_S;
    }
    debugPrint(
        'ClipboardController] 自动检查剪贴板间隔时间: $autoCheckClipboardIntervalS秒');
    if (user.value.isNotLogin ||
        AppLifecyclesStateService.currentState != AppLifecycleState.resumed) {
      debugPrint(
          'ClipboardController] 未登录或应用处于后台，不获取剪贴板列表，下次状态检测在1秒后，登录状态：${user.value.isNotLogin}，应用状态：${AppLifecyclesStateService.currentState}');
      // 当恢复时1秒后获取一次
      _clipboardListTimer = Timer(const Duration(seconds: 1), onTimerTick);
      return;
    }
    onLoadClipboard().then((_) {}).catchError((e) {
      Log.e('ClipboardController] 获取剪贴板列表失败: $e');
    }).whenComplete(() {
      _clipboardListTimer =
          Timer(Duration(seconds: autoCheckClipboardIntervalS), onTimerTick);
    });
  }

  void onCopyClipboard(ClipboardItemModel item) {
    Get.find<ClipboardService>().setCurrentClipboard(item.content ?? '');
  }

  void onUserChanged(UserModel user) {
    if (user.isNotLogin) {
      clipboardList.clear();
      _maxClipboardId = 0;
    }
  }
}
