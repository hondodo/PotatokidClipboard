// ignore_for_file: constant_identifier_names

import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:potatokid_clipboard/framework/utils/app_log.dart';
import 'package:potatokid_clipboard/services/clipboard_service.dart';

class SettingsService extends GetxService {
  static const int MIN_AUTO_CHECK_CLIPBOARD_INTERVAL_S = 1;
  static const int MAX_AUTO_CHECK_CLIPBOARD_INTERVAL_S = 20;
  static const int DEFAULT_AUTO_CHECK_CLIPBOARD_INTERVAL_S = 2;

  /// 是否监控剪贴板
  final Rx<bool> isMonitoringClipboard = true.obs;

  /// 是否自动保存剪贴板
  final Rx<bool> isAutoSaveClipboard = true.obs;

  /// 是否正在同步剪贴板
  final Rx<bool> isSyncingClipboard = false.obs;

  /// 是否正在上传剪贴板
  final Rx<bool> isUploadingClipboard = false.obs;

  /// 是否同步剪贴板失败
  final Rx<bool> isSyncingClipboardFailed = false.obs;

  /// 是否上传剪贴板失败
  final Rx<bool> isUploadingClipboardFailed = false.obs;

  /// 自动检查剪贴板间隔时间(毫秒)
  final Rx<int> autoCheckClipboardIntervalS =
      DEFAULT_AUTO_CHECK_CLIPBOARD_INTERVAL_S.obs;

  /// 是否在启动时隐藏窗口-仅Windows平台有效
  final Rx<bool> isHideWindowOnStartup = true.obs;

  @override
  void onInit() {
    super.onInit();
    try {
      isMonitoringClipboard.value =
          GetStorage().read<bool>('isMonitoringClipboard') ?? true;
      isAutoSaveClipboard.value =
          GetStorage().read<bool>('isAutoSaveClipboard') ?? true;
      autoCheckClipboardIntervalS.value =
          GetStorage().read<int>('autoCheckClipboardIntervalS') ??
              DEFAULT_AUTO_CHECK_CLIPBOARD_INTERVAL_S;
      isHideWindowOnStartup.value =
          GetStorage().read<bool>('isHideWindowOnStartup') ?? true;
    } catch (e) {
      Log.e('SettingsService] 初始化设置失败: $e');
    }
    if (autoCheckClipboardIntervalS.value <
            MIN_AUTO_CHECK_CLIPBOARD_INTERVAL_S ||
        autoCheckClipboardIntervalS.value >
            MAX_AUTO_CHECK_CLIPBOARD_INTERVAL_S) {
      autoCheckClipboardIntervalS.value =
          DEFAULT_AUTO_CHECK_CLIPBOARD_INTERVAL_S;
    }
    isMonitoringClipboard.listen(onIsMonitoringClipboardChanged);
    isAutoSaveClipboard.listen(onIsAutoSaveClipboardChanged);
    autoCheckClipboardIntervalS.listen(onAutoCheckClipboardIntervalSChanged);
    isHideWindowOnStartup.listen(onIsHideWindowOnStartupChanged);
    onSettingsChanged();
    Log.d(
        'SettingsService] 初始化设置: isMonitoringClipboard: ${isMonitoringClipboard.value}, isAutoSaveClipboard: ${isAutoSaveClipboard.value}');
  }

  void onIsMonitoringClipboardChanged(bool value) {
    GetStorage().write('isMonitoringClipboard', value);
    onSettingsChanged();
  }

  void onIsAutoSaveClipboardChanged(bool value) {
    GetStorage().write('isAutoSaveClipboard', value);
    onSettingsChanged();
  }

  void onIsHideWindowOnStartupChanged(bool value) {
    GetStorage().write('isHideWindowOnStartup', value);
  }

  void onAutoCheckClipboardIntervalSChanged(int value) {
    if (value < MIN_AUTO_CHECK_CLIPBOARD_INTERVAL_S ||
        value > MAX_AUTO_CHECK_CLIPBOARD_INTERVAL_S) {
      autoCheckClipboardIntervalS.value =
          DEFAULT_AUTO_CHECK_CLIPBOARD_INTERVAL_S;
    } else {
      autoCheckClipboardIntervalS.value = value;
    }
    GetStorage().write('autoCheckClipboardIntervalS', value);
  }

  void onSettingsChanged() {
    if (isMonitoringClipboard.value) {
      Get.find<ClipboardService>().startMonitoring();
    } else {
      Get.find<ClipboardService>().stopMonitoring();
    }
  }
}
