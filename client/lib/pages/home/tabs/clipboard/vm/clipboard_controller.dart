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
import 'package:potatokid_clipboard/services/clipboard_socket_service.dart';
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

  /// 兜底定时器：WebSocket 已连接时只做低频校验，断开时退回 HTTP 轮询
  Timer? _clipboardListTimer;

  /// WebSocket 正常时的兜底校验间隔（秒）
  static const int _wsCheckIntervalS = 60;

  /// 剪贴板最大id
  int _maxClipboardId = 0;

  final RxList<ClipboardItemModel> clipboardList = <ClipboardItemModel>[].obs;

  Rx<UserModel> get user => Get.find<UserService>().user;

  StreamSubscription<List<ClipboardItemModel>>? _snapshotSub;
  StreamSubscription<ClipboardItemModel>? _newItemSub;
  StreamSubscription<AppLifecycleState>? _lifecycleSub;

  @override
  void onInit() {
    super.onInit();
    user.listen(onUserChanged);
    // WebSocket 推送：连接即回快照，之后只收增量
    _snapshotSub =
        ClipboardSocketService.instance.onSnapshot.listen(onSnapshot);
    _newItemSub =
        ClipboardSocketService.instance.onNewItem.listen(onNewItem);
    // 回前台立即重连，退后台立即断开
    _lifecycleSub = AppLifecyclesStateService.appLifecyclesStateStream
        .listen((_) => onTimerTick());
    onTimerTick();
    textFocusNode.unfocus();
  }

  @override
  void onClose() {
    _clipboardListTimer?.cancel();
    _snapshotSub?.cancel();
    _newItemSub?.cancel();
    _lifecycleSub?.cancel();
    ClipboardSocketService.instance.stop();
    super.onClose();
  }

  /// 合并条目，返回真正新增的数量（按 id 去重）
  int _mergeItems(List<ClipboardItemModel> items) {
    int added = 0;
    for (var item in items) {
      if (item.id <= 0) continue;
      if (clipboardList.any((e) => e.id == item.id)) continue;
      clipboardList.add(item);
      added++;
      if (item.id > _maxClipboardId) {
        _maxClipboardId = item.id;
      }
    }
    if (added == 0) return 0;
    // 排序,按id降序
    clipboardList.sort((a, b) => b.id.compareTo(a.id));
    // 如果超过100条，则删除最早的一条
    while (clipboardList.length > 100) {
      clipboardList.removeLast();
    }
    return added;
  }

  /// 有新增内容时按设置自动写入本机剪贴板
  void _autoSaveFromList(int added) {
    if (added == 0) return;
    bool autoSet = Get.find<SettingsService>().isAutoSaveClipboard.value;
    if (autoSet) {
      var item = clipboardList.first;
      if (item.deviceId != DeviceUtils.instance.deviceId) {
        Get.find<ClipboardService>().setCurrentClipboard(item.content ?? '');
      }
    }
  }

  /// WebSocket 连接后的全量快照
  void onSnapshot(List<ClipboardItemModel> items) {
    final added = _mergeItems(items);
    _autoSaveFromList(added);
    settingsService.isSyncingClipboard.value = true;
    settingsService.isSyncingClipboardFailed.value = false;
    debugPrint(
        'ClipboardController] 收到剪贴板快照: ${items.length}条, 新增$added, 列表长度: ${clipboardList.length}');
  }

  /// 服务端推送的单条新增剪贴板
  void onNewItem(ClipboardItemModel item) {
    final added = _mergeItems([item]);
    _autoSaveFromList(added);
    settingsService.isSyncingClipboard.value = true;
    settingsService.isSyncingClipboardFailed.value = false;
    debugPrint(
        'ClipboardController] 收到剪贴板推送 id=${item.id}, 新增$added, 列表长度: ${clipboardList.length}');
  }

  /// HTTP 兜底拉取（WebSocket 未建立时使用）
  Future<void> onLoadClipboard() async {
    var response = await Get.find<ClipboardRepository>()
        .getClipboardList(fromId: _maxClipboardId);
    final items = response.clipboards ?? const <ClipboardItemModel>[];
    final added = _mergeItems(items);
    _autoSaveFromList(added);
    debugPrint(
        'ClipboardController] 获取剪贴板列表成功，起始id: $_maxClipboardId, 列表长度: ${clipboardList.length}');
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

  bool get _isInBackground =>
      AppLifecyclesStateService.currentState != AppLifecycleState.resumed &&
      (Platform.isAndroid || Platform.isIOS);

  void onTimerTick() {
    _clipboardListTimer?.cancel();
    _clipboardListTimer = null;
    if (user.value.isNotLogin || _isInBackground) {
      ClipboardSocketService.instance.stop();
      debugPrint(
          'ClipboardController] 未登录或应用处于后台，暂不同步后端的剪贴板列表，下次状态检测在1秒后，登录状态：${user.value.isNotLogin}，应用状态：${AppLifecyclesStateService.currentState}');
      // 当恢复时1秒后获取一次
      _clipboardListTimer = Timer(const Duration(seconds: 1), onTimerTick);
      return;
    }

    // 前台且已登录：保持 WebSocket 长连接，由服务端推送增量
    ClipboardSocketService.instance.start();
    if (ClipboardSocketService.instance.isConnected) {
      settingsService.isSyncingClipboard.value = true;
      settingsService.isSyncingClipboardFailed.value = false;
      _clipboardListTimer = Timer(
          const Duration(seconds: _wsCheckIntervalS), onTimerTick);
      return;
    }

    // WebSocket 尚未建立（服务端未升级/网络不通）：退回 HTTP 轮询
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
        'ClipboardController] WebSocket 未连接，按 $autoCheckClipboardIntervalS秒 兜底轮询');
    settingsService.isSyncingClipboard.value = true;
    settingsService.isSyncingClipboardFailed.value = false;
    onLoadClipboard().then((_) {}).catchError((e) {
      Log.e('ClipboardController] 同步后端剪贴板列表失败: $e');
      settingsService.isSyncingClipboardFailed.value = true;
    }).whenComplete(() {
      _clipboardListTimer =
          Timer(Duration(seconds: autoCheckClipboardIntervalS), onTimerTick);
      settingsService.isSyncingClipboard.value =
          ClipboardSocketService.instance.isConnected;
    });
  }

  void onCopyClipboard(ClipboardItemModel item) {
    Get.find<ClipboardService>().setCurrentClipboard(item.content ?? '');
  }

  void onUserChanged(UserModel user) {
    if (user.isNotLogin) {
      ClipboardSocketService.instance.stop();
      clipboardList.clear();
      _maxClipboardId = 0;
    } else {
      // 登录成功立即建连
      onTimerTick();
    }
  }
}
