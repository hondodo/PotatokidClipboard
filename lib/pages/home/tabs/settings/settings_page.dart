import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:potatokid_clipboard/framework/base/base_stateless_sub_widget.dart';
import 'package:potatokid_clipboard/framework/net/net_config.dart';
import 'package:potatokid_clipboard/framework/theme/app_text_theme.dart';
import 'package:potatokid_clipboard/pages/home/tabs/settings/controller/settings_controller.dart';
import 'package:potatokid_clipboard/services/settings_service.dart';

class SettingsPage extends BaseStatelessSubWidget<SettingsController> {
  const SettingsPage({super.key});
  @override
  Widget buildBody(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            children: [
              SwitchListTile(
                title: Text('监控剪贴板'.tr),
                value: controller.isMonitoringClipboard.value,
                onChanged: (value) => controller.onToggleMonitoringClipboard(),
              ),
              SwitchListTile(
                title: Text('自动设置到剪贴板'.tr),
                value: controller.isAutoSaveClipboard.value,
                onChanged: (value) => controller.onToggleAutoSaveClipboard(),
              ),
              if (Platform.isWindows)
                SwitchListTile(
                  title: Text('在启动时隐藏窗口'.tr),
                  value: controller.isHideWindowOnStartup.value,
                  onChanged: (value) =>
                      controller.onToggleHideWindowOnStartup(),
                ),
              Container(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child:
                    Text('自动检查剪贴板间隔时间'.tr, style: AppTextTheme.textStyle.hint),
              ),
              Slider(
                value:
                    (controller.autoCheckClipboardIntervalS.value).toDouble(),
                onChanged: (value) => controller
                    .onChangeAutoCheckClipboardIntervalMs(value.toInt()),
                onChangeEnd: (value) => controller
                    .onEndChangeAutoCheckClipboardIntervalMs(value.toInt()),
                min: SettingsService.MIN_AUTO_CHECK_CLIPBOARD_INTERVAL_S
                    .toDouble(),
                max: SettingsService.MAX_AUTO_CHECK_CLIPBOARD_INTERVAL_S
                    .toDouble(),
                divisions: SettingsService.MAX_AUTO_CHECK_CLIPBOARD_INTERVAL_S -
                    SettingsService.MIN_AUTO_CHECK_CLIPBOARD_INTERVAL_S,
                label: '@interval秒'.trParams({
                  'interval':
                      (controller.autoCheckClipboardIntervalS.value).toString()
                }),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: TextFormField(
                  controller: controller.hostTextController,
                  decoration: InputDecoration(
                    labelText: '主机地址'.tr,
                    hintText: NetConfig.DEFAULT_BASE_HOST,
                    prefixIcon: const Icon(Icons.web),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: Colors.blue, width: 2),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return '请输入主机地址'.tr;
                    }
                    return null;
                  },
                  textInputAction: TextInputAction.next,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: ElevatedButton(
                  onPressed: () {
                    controller.onSaveHost();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                  ),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                    width: double.infinity,
                    alignment: Alignment.center,
                    child: Text(
                      '保存主机地址'.tr,
                      style: AppTextTheme.textStyle.body.buttonText,
                    ),
                  ),
                ),
              ),
              if (controller.newHost.value.isNotEmpty)
                Container(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Text(
                    '*重启后将使用新的主机地址：@host'.trParams({
                      'host': controller.newHost.value,
                    }),
                    style: AppTextTheme.textStyle.body.error,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
