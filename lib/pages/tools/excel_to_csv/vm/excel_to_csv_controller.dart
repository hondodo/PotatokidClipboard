import 'dart:isolate';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:potatokid_clipboard/app/app_enums.dart';
import 'package:potatokid_clipboard/framework/base/base_get_vm.dart';
import 'package:potatokid_clipboard/framework/utils/app_log.dart';
import 'package:potatokid_clipboard/pages/tools/excel_to_csv/model/excel_file_model.dart';
import 'package:potatokid_clipboard/utils/excel_utils.dart';
import 'package:uuid/uuid.dart';

class ExcelToCsvController extends BaseGetVM {
  RxList<ExcelFileModel> excelFiles = <ExcelFileModel>[].obs;
  final TextEditingController saveFolderController = TextEditingController();

  @override
  void onInit() {
    super.onInit();
    String? saveFolder = GetStorage().read<String>('excelToCsvSaveFolder');
    if (saveFolder != null) {
      saveFolderController.text = saveFolder;
    }
  }

  void onSelectSaveFolder() async {
    var folder = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '请选择保存文件夹'.tr,
      initialDirectory: saveFolderController.text,
    );
    if (folder != null) {
      saveFolderController.text = folder;
      GetStorage().write('excelToCsvSaveFolder', folder);
    }
  }

  Future<void> onAddExcelFiles() async {
    var files = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        allowMultiple: true);
    if (files != null) {
      for (var file in files.files) {
        // 用uuid生成唯一标识
        final id = Uuid().v4();
        excelFiles.add(ExcelFileModel(id: id, file: file));
      }
    }
  }

  Future<void> onConvertExcelFiles() async {
    final saveFolder = saveFolderController.text;
    for (var excelFile in excelFiles) {
      String id = excelFile.id;
      excelFile.convertStatus.value = ExcelToCsvConvertStatus.converting;
      excelFile.convertError.value = '';
      update([id]);

      // 提取基本类型数据，避免在 Isolate 中传递 Flutter 对象
      final filePath = excelFile.file.path;
      final fileName = excelFile.name;

      if (filePath == null) {
        excelFile.convertStatus.value = ExcelToCsvConvertStatus.failed;
        excelFile.convertError.value = '文件路径为空';
        update([id]);
        continue;
      }

      // 在线程里运行，只传递基本类型数据
      try {
        await Isolate.run(() async {
          await ExcelUtils.convertExcelToCsvInIsolate(
              filePath, fileName, saveFolder);
        });
        // 在主线程中更新状态
        var item = excelFiles.firstWhereOrNull((element) => element.id == id);
        if (item != null) {
          item.convertStatus.value = ExcelToCsvConvertStatus.completed;
          item.convertError.value = '';
        }
      } catch (e) {
        // 在主线程中更新错误状态
        var item = excelFiles.firstWhereOrNull((element) => element.id == id);
        if (item != null) {
          item.convertStatus.value = ExcelToCsvConvertStatus.failed;
          item.convertError.value = e.toString();
        }
      }
      try {
        update([id]);
      } catch (e) {
        Log.e('更新状态失败: $e');
      }
    }
  }

  Future<void> onClearExcelFiles() async {
    excelFiles.clear();
  }
}
