import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:potatokid_clipboard/app/app_enums.dart';
import 'package:potatokid_clipboard/framework/base/base_get_vm.dart';
import 'package:potatokid_clipboard/pages/home/tabs/excel_to_csv/model/excel_file_model.dart';
import 'package:potatokid_clipboard/utils/excel_utils.dart';

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
        excelFiles.add(ExcelFileModel(file: file));
      }
    }
  }

  Future<void> onConvertExcelFiles() async {
    for (var excelFile in excelFiles) {
      excelFile.convertStatus.value = ExcelToCsvConvertStatus.converting;
      update([excelFile.name]);
      await ExcelUtils.convertExcelToCsv(
          excelFile.file, saveFolderController.text);
      excelFile.convertStatus.value = ExcelToCsvConvertStatus.completed;
      update([excelFile.name]);
    }
  }

  Future<void> onClearExcelFiles() async {
    excelFiles.clear();
  }
}
