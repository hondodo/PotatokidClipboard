import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:open_file/open_file.dart';
import 'package:potatokid_clipboard/app/app_cache.dart';
import 'package:potatokid_clipboard/framework/base/base_get_vm.dart';
import 'package:potatokid_clipboard/framework/utils/app_log.dart';
import 'package:potatokid_clipboard/pages/home/tabs/files/model/file_item_model.dart';
import 'package:potatokid_clipboard/pages/home/tabs/files/model/file_list_model.dart';
import 'package:potatokid_clipboard/pages/home/tabs/files/repository/file_repository.dart';
import 'package:potatokid_clipboard/user/user_service.dart';
import 'package:potatokid_clipboard/utils/device_utils.dart';
import 'package:potatokid_clipboard/utils/dialog_helper.dart';
import 'package:potatokid_clipboard/utils/error_utils.dart';
import 'package:potatokid_clipboard/utils/file_path.dart';
import 'package:share_plus/share_plus.dart';

class FileDownloadController extends BaseGetVM {
  FileRepository get fileRepository => Get.find<FileRepository>();
  final Rx<FileListModel?> fileList = Rx<FileListModel?>(null);
  final RxList<FileItemModel> uploadingFiles = <FileItemModel>[].obs;
  late String iphoneTip;

  @override
  void onInit() {
    super.onInit();
    iphoneTip =
        '注：在iPhone下，只能选择本程序目录下的目录（我的iPhone->Poatatokid Clipboard），否则无法下载文件'.tr;
    onRefresh();
  }

  Future<FileListModel> getFileList() async {
    var result = await fileRepository.getFileList();
    // 从缓存更新本地文件名
    for (var file in result.files ?? []) {
      file.localFilename =
          AppCache.instance.getWebFileTolocalFilename(file.name);
      bool exists = false;
      if (file.localFilename != null) {
        exists = File(file.localFilename ?? '').existsSync();
      }
      file.isDownloaded = exists;
    }
    fileList.value = result;
    return result;
  }

  Future<void> onRefresh() async {
    getFileList().responseWithStatus(this);
  }

  Future<void> downloadFile(FileItemModel file) async {
    // 检查是否已登录
    if (Get.find<UserService>().user.value.isNotLogin) {
      ErrorUtils.showErrorToast('请先登录');
      return;
    }
    try {
      String? saveDir = await FilePicker.platform.getDirectoryPath();
      if (saveDir == null) {
        ErrorUtils.showErrorToast('用户取消了保存操作');
        return;
      }
      String saveFilename = FilePath.join(saveDir, file.name).unique().path;
      bool success = await fileRepository.downloadFile(
        filename: file.name,
        saveFilename: saveFilename,
        onReceiveProgress: (count, total) {
          debugPrint('[downloadFile] 下载进度: $count / $total');
          file.count = count;
          file.total = total;
          // 更新文件列表
          fileList.value?.files
              ?.firstWhere((element) => element.name == file.name)
              .count = count;
          fileList.value?.files
              ?.firstWhere((element) => element.name == file.name)
              .total = total;
          fileList.value = fileList.value;
          update([file.name]);
        },
      );
      if (!success) {
        DialogHelper.showTextToast('下载失败，请稍后再试'.tr);
        fileList.value?.files
            ?.firstWhere((element) => element.name == file.name)
            .isDownloadFailed = true;
        fileList.value?.files
            ?.firstWhere((element) => element.name == file.name)
            .isDownloaded = false;
        fileList.value?.files
            ?.firstWhere((element) => element.name == file.name)
            .localFilename = null;
        fileList.value = fileList.value;
        update([file.name]);
        return;
      }
      AppCache.instance.setWebFileTolocalFilename(file.name, saveFilename);
      fileList.value?.files
          ?.firstWhere((element) => element.name == file.name)
          .isDownloadFailed = false;
      fileList.value?.files
          ?.firstWhere((element) => element.name == file.name)
          .isDownloaded = true;
      fileList.value?.files
          ?.firstWhere((element) => element.name == file.name)
          .localFilename = saveFilename;
      fileList.value = fileList.value;
      update([file.name]);
      DialogHelper.showTextToast(
          '下载成功，已保存到：\n@filename'.trParams({'filename': saveFilename}));
    } catch (e) {
      Log.e('downloadFile error: $e');

      if (Platform.isIOS && e is PathAccessException) {
        DialogHelper.showTextToast(
            '@tip\n@error'.trParams({'tip': iphoneTip, 'error': '$e'}));
      } else {
        ErrorUtils.showErrorToast(
            '打开保存对话框失败: @error'.trParams({'error': '$e'}));
      }
    }
  }

  Future<void> shareFile(FileItemModel file) async {
    // 先检查文件是否存在
    bool exists = false;
    if (file.localFilename != null) {
      exists = File(file.localFilename ?? '').existsSync();
    }
    if (!exists) {
      fileList.value?.files
          ?.firstWhere((element) => element.name == file.name)
          .isDownloaded = false;
      fileList.value?.files
          ?.firstWhere((element) => element.name == file.name)
          .count = 0;
      fileList.value?.files
          ?.firstWhere((element) => element.name == file.name)
          .total = 0;
      update([file.name]);
      DialogHelper.showTextToast('文件不存在，无法分享'.tr);
      return;
    }

    final params = ShareParams(
      text: '分享文件：@filename'.trParams({'filename': file.name}),
      files: [XFile(file.localFilename ?? '')],
    );

    final result = await SharePlus.instance.share(params);

    if (result.status == ShareResultStatus.success) {
      DialogHelper.showTextToast('分享成功'.tr);
    } else if (result.status == ShareResultStatus.dismissed) {
      DialogHelper.showTextToast('用户取消了分享'.tr);
    } else if (result.status == ShareResultStatus.unavailable) {
      DialogHelper.showTextToast('分享失败，请稍后再试'.tr);
    } else {
      DialogHelper.showTextToast('分享失败'.tr);
    }
  }

  Future<void> onDoubleTapFile(FileItemModel file) async {
    if (!DeviceUtils.instance.isMobile()) {
      // 移动端不允许双击打开
      return;
    }
    if (!file.isDownloaded) {
      await downloadFile(file);
    }
    await openFile(file);
  }

  Future<void> openFile(FileItemModel file) async {
    if (!file.isDownloaded) {
      DialogHelper.showTextToast('文件未下载'.tr);
      return;
    }
    if (file.localFilename == null) {
      DialogHelper.showTextToast('文件不存在'.tr);
      return;
    }
    await OpenFile.open(file.localFilename ?? '');
  }

  Future<void> onReuploadFile(FileItemModel file) async {
    file.isUploading = true;
    file.isUploadFailed = false;
    file.uploadCount = 0;
    file.uploadTotal = 0;
    update([file.localFilename ?? '']);
  }

  Future<void> onUploadFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any);
    if (result != null) {
      final file = result.files.first;
      final filename = file.name;
      final filepath = file.path;
      if (filepath == null) {
        DialogHelper.showTextToast('请选择要上传的文件'.tr);
        return;
      }
      // 检查是否有正在上传相同的文件
      if (uploadingFiles.any((element) =>
          element.localFilename == filepath && element.isUploading)) {
        DialogHelper.showTextToast('文件正在上传中，请稍后再试'.tr);
        return;
      }

      // 否则先删除同名文件
      if (uploadingFiles.any((element) => element.localFilename == filepath)) {
        uploadingFiles
            .removeWhere((element) => element.localFilename == filepath);
      }

      FileItemModel model = FileItemModel(
          sName: filename,
          sSize: file.size,
          sUploadTime: DateTime.now().toIso8601String());
      model.localFilename = filepath;
      model.isUploading = true;
      model.isUploadFailed = false;
      model.isUploadCompleted = false;
      model.uploadCount = 0;
      model.uploadTotal = file.size;
      uploadingFiles.insert(0, model);
      update([model.localFilename ?? '']);
      final response = await fileRepository.uploadFile(filename, filepath,
          onSendProgress: (count, total) {
        debugPrint('[FileUploadController] 上传进度: $count / $total');
        uploadingFiles
            .firstWhere((element) => element.localFilename == filepath)
            .uploadCount = count;
        uploadingFiles
            .firstWhere((element) => element.localFilename == filepath)
            .uploadTotal = total;
        update([model.localFilename ?? '']);
      });
      if (response != null) {
        uploadingFiles
            .firstWhere((element) => element.localFilename == filepath)
            .isUploading = false;
        uploadingFiles
            .firstWhere((element) => element.localFilename == filepath)
            .isUploadCompleted = true;
        update([model.localFilename ?? '']);
        DialogHelper.showTextToast('上传成功'.tr);
        onRefresh();
      } else {
        uploadingFiles
            .firstWhere((element) => element.localFilename == filepath)
            .isUploading = false;
        uploadingFiles
            .firstWhere((element) => element.localFilename == filepath)
            .isUploadFailed = true;
        update([model.localFilename ?? '']);
      }
    } else {
      DialogHelper.showTextToast('未选择文件'.tr);
    }
  }

  Future<void> onCloseUploadFile(FileItemModel file) async {
    uploadingFiles.remove(file);
  }
}
