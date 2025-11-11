import 'dart:async';
import 'dart:io';

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
import 'package:potatokid_clipboard/utils/device_utils.dart';
import 'package:potatokid_clipboard/utils/dialog_helper.dart';
import 'package:potatokid_clipboard/utils/error_utils.dart';

class ClipboardController extends BaseGetVM {
  final TextEditingController textController = TextEditingController();
  final FocusNode textFocusNode = FocusNode();
  SettingsService get settingsService => Get.find<SettingsService>();

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
    textFocusNode.unfocus();
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
      bool autoSet = Get.find<SettingsService>().isAutoSaveClipboard.value;
      if (autoSet) {
        var item = clipboardList.first;
        if (item.deviceId != DeviceUtils.instance.deviceId) {
          Get.find<ClipboardService>().setCurrentClipboard(item.content ?? '');
        }
      }
    }
    debugPrint(
        'ClipboardController] 获取剪贴板列表成功，起始id: $_maxClipboardId, 列表长度: ${response.clipboards?.length}');
  }

  Future<void> onSetClipboard() async {
    try {
      if (textController.text.isEmpty) {
        DialogHelper.showTextToast('请输入内容'.tr);
        return;
      }
      textFocusNode.unfocus();
      DialogHelper.showTextLoading();
      await Get.find<ClipboardRepository>().setClipboard(textController.text);
      Get.find<ClipboardService>().setCurrentClipboard(textController.text);
      textController.clear();
    } catch (e) {
      ErrorUtils.showErrorToast(e);
    }
    DialogHelper.dismiss();
    DialogHelper.showTextToast('添加到剪贴板成功'.tr);
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
        'ClipboardController] 自动同步后端剪贴板列表间隔时间: $autoCheckClipboardIntervalS秒');
    if (user.value.isNotLogin ||
        ((AppLifecyclesStateService.currentState != AppLifecycleState.resumed &&
            (Platform.isAndroid || Platform.isIOS)))) {
      debugPrint(
          'ClipboardController] 未登录或应用处于后台，暂不同步后端的剪贴板列表，下次状态检测在1秒后，登录状态：${user.value.isNotLogin}，应用状态：${AppLifecyclesStateService.currentState}');
      // 当恢复时1秒后获取一次
      _clipboardListTimer = Timer(const Duration(seconds: 1), onTimerTick);
      return;
    }
    settingsService.isSyncingClipboard.value = true;
    settingsService.isSyncingClipboardFailed.value = false;
    onLoadClipboard().then((_) {}).catchError((e) {
      Log.e('ClipboardController] 同步后端剪贴板列表失败: $e');
      settingsService.isSyncingClipboardFailed.value = true;
    }).whenComplete(() {
      _clipboardListTimer =
          Timer(Duration(seconds: autoCheckClipboardIntervalS), onTimerTick);
      settingsService.isSyncingClipboard.value = false;
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
