import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:potatokid_clipboard/framework/app/app_values.dart';
import 'package:potatokid_clipboard/framework/base/base_get_vm.dart';
import 'package:potatokid_clipboard/services/settings_service.dart';
import 'package:potatokid_clipboard/utils/dialog_helper.dart';

class SettingsController extends BaseGetVM {
  final SettingsService settingsService = Get.find<SettingsService>();
  Rx<bool> get isMonitoringClipboard => settingsService.isMonitoringClipboard;
  Rx<bool> get isAutoSaveClipboard => settingsService.isAutoSaveClipboard;
  Rx<bool> get isHideWindowOnStartup => settingsService.isHideWindowOnStartup;
  Rx<int> autoCheckClipboardIntervalS =
      SettingsService.DEFAULT_AUTO_CHECK_CLIPBOARD_INTERVAL_S.obs;
  Rx<String> newHost = ''.obs;

  /// 主机地址
  final TextEditingController hostTextController = TextEditingController();

  @override
  void onInit() {
    super.onInit();
    autoCheckClipboardIntervalS.value =
        settingsService.autoCheckClipboardIntervalS.value;
    hostTextController.text = AppValues.getHost();
  }

  void onToggleMonitoringClipboard() {
    isMonitoringClipboard.value = !isMonitoringClipboard.value;
  }

  void onToggleAutoSaveClipboard() {
    isAutoSaveClipboard.value = !isAutoSaveClipboard.value;
  }

  void onToggleHideWindowOnStartup() {
    isHideWindowOnStartup.value = !isHideWindowOnStartup.value;
  }

  void onChangeAutoCheckClipboardIntervalMs(int value) {
    if (value < SettingsService.MIN_AUTO_CHECK_CLIPBOARD_INTERVAL_S ||
        value > SettingsService.MAX_AUTO_CHECK_CLIPBOARD_INTERVAL_S) {
      autoCheckClipboardIntervalS.value =
          SettingsService.DEFAULT_AUTO_CHECK_CLIPBOARD_INTERVAL_S;
    } else {
      autoCheckClipboardIntervalS.value = value;
    }
  }

  void onEndChangeAutoCheckClipboardIntervalMs(int value) {
    if (value < SettingsService.MIN_AUTO_CHECK_CLIPBOARD_INTERVAL_S ||
        value > SettingsService.MAX_AUTO_CHECK_CLIPBOARD_INTERVAL_S) {
      autoCheckClipboardIntervalS.value =
          SettingsService.DEFAULT_AUTO_CHECK_CLIPBOARD_INTERVAL_S;
    } else {
      autoCheckClipboardIntervalS.value = value;
    }
    // 更新设置服务中的自动检查剪贴板间隔时间
    settingsService.autoCheckClipboardIntervalS.value =
        autoCheckClipboardIntervalS.value;
  }

  void onSaveHost() {
    var host = hostTextController.text.trim();
    if (host.isEmpty) {
      DialogHelper.showTextToast('请输入主机地址'.tr);
      return;
    }
    newHost.value = host;
    AppValues.setHost(host);
    DialogHelper.showTextToast('主机地址保存成功'.tr);
  }
}
