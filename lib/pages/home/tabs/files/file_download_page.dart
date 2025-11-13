import 'package:custom_refresh_indicator/custom_refresh_indicator.dart';
import 'package:file_icon/file_icon.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:potatokid_clipboard/framework/base/base_stateless_sub_widget.dart';
import 'package:potatokid_clipboard/framework/theme/app_text_theme.dart';
import 'package:potatokid_clipboard/pages/home/tabs/files/controller/file_download_controller.dart';
import 'package:potatokid_clipboard/pages/home/tabs/files/model/file_item_model.dart';

class FileDownloadPage extends BaseStatelessSubWidget<FileDownloadController> {
  const FileDownloadPage({super.key});

  @override
  Widget buildBody(BuildContext context) {
    return CustomMaterialIndicator(
      onRefresh: () async {
        await controller.onRefresh();
      },
      scrollableBuilder: (context, child, controller) {
        // 在 Windows 平台上启用鼠标拖动滚动
        return ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(
            dragDevices: {
              PointerDeviceKind.mouse,
              PointerDeviceKind.touch,
              PointerDeviceKind.stylus,
              PointerDeviceKind.trackpad,
            },
          ),
          child: child,
        );
      },
      child: ListView.builder(
        itemCount: controller.fileList.value?.files?.length ?? 0,
        itemBuilder: (context, index) {
          return Container(
            padding: const EdgeInsets.only(
              left: 16,
              right: 16,
            ),
            child: getFileItemCard(
                controller.fileList.value?.files?[index] ?? FileItemModel()),
          );
        },
      ),
    );
  }

  Widget getFileItemCard(FileItemModel file) {
    return Card(
      child: Container(
        padding: const EdgeInsets.only(top: 8, bottom: 8, left: 4, right: 4),
        child: Row(
          children: [
            // 图标
            FileIcon(file.name, size: 32),
            const SizedBox(width: 8),
            // [文件名、大小]
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  // 文件名
                  Text(
                    file.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextTheme.textStyle.body,
                  ),
                  // 上传时间
                  Text(
                    file.uploadTimeFormatted,
                    style: AppTextTheme.textStyle.hint
                        .resize(AppTextTheme.fontSizeSmall),
                  ),
                  // 大小
                  Text(
                    file.size.toString(),
                    style: AppTextTheme.textStyle.hint
                        .resize(AppTextTheme.fontSizeSmall),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // 下载按钮
            IconButton(
                onPressed: () {
                  controller.downloadFile(file);
                },
                icon: const Icon(
                  Icons.download,
                  color: AppTextTheme.primaryColor,
                )),
          ],
        ),
      ),
    );
  }
}
