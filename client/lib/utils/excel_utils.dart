import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:potatokid_clipboard/utils/file_path.dart';

class ExcelUtils {
  /// 在 Isolate 中使用的转换方法，只接受基本类型参数
  static Future<void> convertExcelToCsvInIsolate(
      String filePath, String fileName, String saveDirectory) async {
    var ioFile = File(filePath);
    var bytes = await ioFile.readAsBytes();
    var excel = Excel.decodeBytes(bytes);
    // 1、读取每个表单
    // 2、每个表单转换为csv
    // 3、保存到指定目录
    for (var sheet in excel.tables.keys) {
      var sheetObject = excel.tables[sheet]!;
      List<List<dynamic>> rows = [];
      // 将表里的每一行组成一个List<dynamic>
      // 组成List<List<dynamic>>
      for (var row in sheetObject.rows) {
        List<dynamic> rowData = [];
        for (var cell in row) {
          rowData.add(cell?.value ?? '');
        }
        rows.add(rowData);
      }
      String savePath =
          FilePath.join(saveDirectory, '${fileName.split('.')[0]}_$sheet.csv')
              .path;
      final res = const ListToCsvConverter().convert(rows);
      // 使用 UTF-8 BOM 编码保存，确保 Excel 能正确识别中文
      final utf8Bytes = utf8.encode(res);
      final List<int> bytesWithBom = [0xEF, 0xBB, 0xBF, ...utf8Bytes];
      await File(savePath).writeAsBytes(bytesWithBom);
    }
  }

  /// 保留原有方法以保持兼容性
  static Future<void> convertExcelToCsv(
      PlatformFile file, String saveDirectory) async {
    if (file.path == null) {
      return;
    }
    await convertExcelToCsvInIsolate(file.path!, file.name, saveDirectory);
  }
}
