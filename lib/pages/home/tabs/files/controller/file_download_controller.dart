import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:potatokid_clipboard/framework/base/base_get_vm.dart';
import 'package:potatokid_clipboard/framework/utils/app_log.dart';
import 'package:potatokid_clipboard/pages/home/tabs/files/model/file_item_model.dart';
import 'package:potatokid_clipboard/pages/home/tabs/files/model/file_list_model.dart';
import 'package:potatokid_clipboard/pages/home/tabs/files/repository/file_repository.dart';
import 'package:potatokid_clipboard/user/user_service.dart';
import 'package:potatokid_clipboard/utils/dialog_helper.dart';
import 'package:potatokid_clipboard/utils/error_utils.dart';
import 'package:potatokid_clipboard/utils/file_path.dart';

class FileDownloadController extends BaseGetVM {
  FileRepository get fileRepository => Get.find<FileRepository>();
  final Rx<FileListModel?> fileList = Rx<FileListModel?>(null);

  @override
  void onInit() {
    super.onInit();
    onRefresh();
  }

  Future<FileListModel> getFileList() async {
    var result = await fileRepository.getFileList();
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
        },
      );
      if (!success) {
        DialogHelper.showTextToast('下载失败，请稍后再试'.tr);
        return;
      }
      DialogHelper.showTextToast(
          '下载成功，已保存到：\n@filename'.trParams({'filename': saveFilename}));
    } catch (e) {
      Log.e('downloadFile error: $e');
      ErrorUtils.showErrorToast('打开保存对话框失败: $e');
    }
  }
}
