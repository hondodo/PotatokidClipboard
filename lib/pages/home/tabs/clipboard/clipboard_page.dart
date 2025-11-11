import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:potatokid_clipboard/app/app_enums.dart';
import 'package:potatokid_clipboard/framework/base/base_stateless_sub_widget.dart';
import 'package:potatokid_clipboard/framework/theme/app_text_theme.dart';
import 'package:potatokid_clipboard/pages/home/tabs/clipboard/model/clipboard_item_model.dart';
import 'package:potatokid_clipboard/pages/home/tabs/clipboard/vm/clipboard_controller.dart';
import 'package:potatokid_clipboard/utils/device_utils.dart';

class ClipboardPage extends BaseStatelessSubWidget<ClipboardController> {
  const ClipboardPage({super.key});

  @override
  Widget buildBody(BuildContext context) {
    if (controller.user.value.isNotLogin) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('请登录后使用'.tr, style: AppTextTheme.textStyle.body),
        ),
      );
    }
    return GestureDetector(
      onTap: () => controller.textFocusNode.unfocus(),
      child: Column(
        children: [
          Padding(
            padding:
                const EdgeInsets.only(left: 16, right: 16, top: 8, bottom: 4),
            child: Row(
              children: [
                Expanded(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxHeight: 120,
                    ),
                    child: Container(
                      padding: EdgeInsets.zero,
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey, width: 1),
                      ),
                      child: TextField(
                        minLines: 1,
                        maxLines: null,
                        controller: controller.textController,
                        focusNode: controller.textFocusNode,
                        style: AppTextTheme.textStyle.body,
                        decoration: InputDecoration(
                          hintText: '请输入内容'.tr,
                          hintStyle: AppTextTheme.textStyle.hint,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                          isDense: true,
                          border: const OutlineInputBorder(
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: const OutlineInputBorder(
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                ElevatedButton(
                  onPressed: controller.onSetClipboard,
                  child: Text('添加'.tr, style: AppTextTheme.textStyle.body),
                ),
              ],
            ),
          ),
          // Padding(
          //   padding:
          //       const EdgeInsets.only(left: 16, right: 16, top: 2, bottom: 16),
          //   child: ElevatedButton(
          //     onPressed: controller.onSetClipboard,
          //     child: Text('添加到剪贴板'.tr, style: AppTextTheme.textStyle.body),
          //   ),
          // ),
          const SizedBox(height: 4),
          Expanded(
            child: CustomScrollView(
              slivers: [
                SliverList.builder(
                  itemCount: controller.clipboardList.length,
                  itemBuilder: (context, index) {
                    var item = controller.clipboardList[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: buildClipboardCard(item),
                    );
                  },
                )
              ],
            ),
          ),
          const SizedBox(height: 4),
          Container(
            padding:
                const EdgeInsets.only(left: 16, right: 16, top: 2, bottom: 2),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.05),
              border: Border(
                  bottom: BorderSide(
                      color: Colors.black.withOpacity(0.1), width: 1)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    // 上传图标
                    Icon(Icons.upload,
                        size: 12,
                        color: controller.settingsService
                                .isUploadingClipboardFailed.value
                            ? AppTextTheme.errorColor
                            : controller
                                    .settingsService.isUploadingClipboard.value
                                ? AppTextTheme.primaryColor
                                : AppTextTheme.hintColor),
                    const SizedBox(width: 4),
                    // 同步图标
                    Icon(Icons.sync,
                        size: 12,
                        color: controller
                                .settingsService.isSyncingClipboardFailed.value
                            ? AppTextTheme.errorColor
                            : controller
                                    .settingsService.isSyncingClipboard.value
                                ? AppTextTheme.primaryColor
                                : AppTextTheme.hintColor),
                  ],
                ),
                Row(
                  children: [
                    // 监控图标
                    Icon(
                      Icons.monitor,
                      size: 12,
                      color:
                          controller.settingsService.isMonitoringClipboard.value
                              ? AppTextTheme.primaryColor
                              : AppTextTheme.hintColor,
                    ),
                    const SizedBox(width: 4),
                    // 自动设置图标
                    Icon(Icons.auto_mode,
                        size: 12,
                        color:
                            controller.settingsService.isAutoSaveClipboard.value
                                ? AppTextTheme.primaryColor
                                : AppTextTheme.hintColor),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  IconData getOsIcon(OsType os) {
    switch (os) {
      case OsType.windows:
        return Icons.computer;
      case OsType.ios:
        return Icons.apple;
      case OsType.android:
        return Icons.android;
      case OsType.linux:
        return Icons.computer;
      case OsType.macos:
        return Icons.computer;
      default:
        return Icons.device_unknown;
    }
  }

  Widget buildClipboardCard(ClipboardItemModel item) {
    String content = item.content ?? '';
    if (content.length > 100) {
      content = '${content.substring(0, 100)}...';
    }
    content = content.replaceAll('\n', ' ');
    var card = Card(
      child: Container(
        padding: const EdgeInsets.only(left: 16, right: 4, top: 8, bottom: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 时间
                  Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(item.createdAtFormatted,
                            style: AppTextTheme.textStyle.hint),
                        Row(
                          children: [
                            Icon(getOsIcon(item.os),
                                size: 12, color: AppTextTheme.hintColor),
                            if (item.deviceId ==
                                DeviceUtils.instance.deviceId) ...[
                              const SizedBox(width: 4),
                              Text('本设备'.tr,
                                  style: AppTextTheme.textStyle.hint),
                            ],
                          ],
                        ),
                      ]),

                  // 内容, 最长显示50个字符，超出显示省略号
                  Text(
                    content,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextTheme.textStyle.body,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
                onPressed: () => controller.onCopyClipboard(item),
                icon: const Icon(Icons.copy, size: 14, color: Colors.blue)),
          ],
        ),
      ),
    );
    return SelectionArea(
      child: GestureDetector(
        onTap: () => controller.textFocusNode.unfocus(),
        child: card,
      ),
    );
  }
}
