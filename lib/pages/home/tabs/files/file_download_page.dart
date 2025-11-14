import 'dart:io';

import 'package:custom_refresh_indicator/custom_refresh_indicator.dart';
import 'package:file_icon/file_icon.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
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
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.only(
                left: 16,
                right: 16,
                top: 8,
                bottom: 16,
              ),
              child: ElevatedButton(
                  onPressed: () {
                    controller.onUploadFile();
                  },
                  child: Text('上传文件'.tr)),
            ),
          ),
          SliverList.builder(
            itemCount: controller.uploadingFiles.length,
            itemBuilder: (context, index) {
              return Container(
                padding: const EdgeInsets.only(
                  left: 16,
                  right: 16,
                ),
                child:
                    getUploadingFileItemCard(controller.uploadingFiles[index]),
              );
            },
          ),
          if (Platform.isIOS)
            SliverToBoxAdapter(
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Text(
                  controller.iphoneTip,
                  style: AppTextTheme.textStyle.body.hint,
                ),
              ),
            ),
          SliverList.builder(
            itemCount: controller.fileList.value?.files?.length ?? 0,
            itemBuilder: (context, index) {
              return Container(
                padding: const EdgeInsets.only(
                  left: 16,
                  right: 16,
                ),
                child: getFileItemCard(
                    controller.fileList.value?.files?[index] ??
                        FileItemModel()),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget getFileItemCard(FileItemModel file) {
    return GetBuilder<FileDownloadController>(
      id: file.name,
      builder: (controller) {
        return Card(
          clipBehavior: Clip.hardEdge,
          child: Stack(
            // 进度条
            children: [
              Visibility(
                visible: file.isDownloadFailed ||
                    file.isDownloaded ||
                    file.total > 0,
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.transparent,
                  ),
                  width: double.infinity,
                  height: 4,
                  child: LinearProgressIndicator(
                    value: file.isDownloadFailed
                        ? 1
                        : file.isDownloaded
                            ? 1
                            : file.count / file.total,
                    color: file.isDownloadFailed
                        ? AppTextTheme.errorColor
                        : file.isDownloaded
                            ? AppTextTheme.successColor
                            : AppTextTheme.primaryColor.withOpacity(0.5),
                    backgroundColor: AppTextTheme.hintColor.withOpacity(0.5),
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.only(top: 8, bottom: 8, left: 4, right: 4),
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
                            file.fileSizeFormatted,
                            style: AppTextTheme.textStyle.hint
                                .resize(AppTextTheme.fontSizeSmall),
                          ),
                          Visibility(
                            visible:
                                file.isDownloaded && file.localFilename != null,
                            child: Text(
                              '文件已保存到：@filename'.trParams(
                                  {'filename': file.localFilename ?? ''}),
                              style: AppTextTheme.textStyle.hint
                                  .resize(AppTextTheme.fontSizeSmall),
                            ),
                          )
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // 下载按钮
                    Row(children: [
                      IconButton(
                        onPressed: () {
                          controller.downloadFile(file);
                        },
                        icon: const Icon(
                          Icons.download,
                          color: AppTextTheme.primaryColor,
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Visibility(
                        visible: file.isDownloaded,
                        child: IconButton(
                          onPressed: () {
                            controller.shareFile(file);
                          },
                          icon: const Icon(
                            Icons.share,
                            color: AppTextTheme.primaryColor,
                            size: 16,
                          ),
                        ),
                      )
                    ]),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget getUploadingFileItemCard(FileItemModel file) {
    return GetBuilder<FileDownloadController>(
      id: file.localFilename ?? '',
      builder: (controller) {
        return Card(
          clipBehavior: Clip.hardEdge,
          child: Stack(
            // 进度条
            children: [
              Visibility(
                visible: file.isUploadFailed ||
                    file.isUploading ||
                    file.uploadTotal > 0 ||
                    file.isUploadCompleted,
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.transparent,
                  ),
                  width: double.infinity,
                  height: 4,
                  child: LinearProgressIndicator(
                    value: file.isUploadFailed
                        ? 1
                        : file.isUploadCompleted
                            ? 1
                            : file.uploadCount / file.uploadTotal,
                    color: file.isUploadFailed
                        ? AppTextTheme.errorColor
                        : file.isUploadCompleted
                            ? AppTextTheme.successColor
                            : AppTextTheme.primaryColor.withOpacity(0.5),
                    backgroundColor: AppTextTheme.hintColor.withOpacity(0.5),
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.only(top: 8, bottom: 8, left: 4, right: 4),
                child: Row(
                  children: [
                    // 图标
                    Stack(
                      children: [
                        FileIcon(file.name, size: 32),
                        const Positioned(
                            bottom: 0,
                            right: 0,
                            child: Icon(Icons.upload,
                                color: AppTextTheme.primaryColor, size: 16)),
                      ],
                    ),
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
                            file.fileSizeFormatted,
                            style: AppTextTheme.textStyle.hint
                                .resize(AppTextTheme.fontSizeSmall),
                          ),
                        ],
                      ),
                    ),
                    // 上传失败时显示重试按钮
                    Visibility(
                      visible: file.isUploadFailed,
                      child: const SizedBox(width: 8),
                    ),
                    Visibility(
                      visible: file.isUploadFailed,
                      child: IconButton(
                        onPressed: () {
                          controller.onReuploadFile(file);
                        },
                        icon: const Icon(
                          Icons.refresh,
                          color: AppTextTheme.primaryColor,
                          size: 16,
                        ),
                      ),
                    ),
                    Visibility(
                      visible: file.isUploadCompleted,
                      child: const SizedBox(width: 8),
                    ),
                    // 关闭（删除记录）按钮
                    Visibility(
                      visible: file.isUploadCompleted || file.isUploadFailed,
                      child: IconButton(
                        onPressed: () {
                          controller.onCloseUploadFile(file);
                        },
                        icon: const Icon(
                          Icons.close,
                          color: AppTextTheme.errorColor,
                          size: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
