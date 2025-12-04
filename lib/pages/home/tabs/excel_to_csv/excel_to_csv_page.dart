import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:potatokid_clipboard/app/app_enums.dart';
import 'package:potatokid_clipboard/framework/base/base_stateless_sub_widget.dart';
import 'package:potatokid_clipboard/framework/theme/app_text_theme.dart';
import 'package:potatokid_clipboard/pages/home/tabs/excel_to_csv/model/excel_file_model.dart';
import 'package:potatokid_clipboard/pages/home/tabs/excel_to_csv/vm/excel_to_csv_controller.dart';

class ExcelToCsvPage extends BaseStatelessSubWidget<ExcelToCsvController> {
  const ExcelToCsvPage({super.key});

  @override
  Widget buildBody(BuildContext context) {
    return Column(
      children: [
        SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.only(left: 16, right: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ElevatedButton(
                onPressed: controller.onAddExcelFiles,
                child: Text('添加文件'.tr, style: AppTextTheme.textStyle.body),
              ),
              SizedBox(width: 16),
              Row(
                children: [
                  ElevatedButton(
                    onPressed: controller.onConvertExcelFiles,
                    child: Text('开始转换'.tr, style: AppTextTheme.textStyle.body),
                  ),
                  SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: controller.onClearExcelFiles,
                    child: Text('清空'.tr, style: AppTextTheme.textStyle.body),
                  ),
                ],
              ),
            ],
          ),
        ),
        SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(left: 16, right: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: TextField(
                  style: AppTextTheme.textStyle.body,
                  decoration: InputDecoration(
                    hintText: '请选择保存文件夹'.tr,
                    hintStyle: AppTextTheme.textStyle.hint,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  controller: controller.saveFolderController,
                ),
              ),
              SizedBox(width: 16),
              ElevatedButton(
                onPressed: controller.onSelectSaveFolder,
                child: Text('选择'.tr, style: AppTextTheme.textStyle.body),
              ),
            ],
          ),
        ),
        SizedBox(height: 16),
        Expanded(
          child: CustomScrollView(
            slivers: [
              SliverList.builder(
                itemCount: controller.excelFiles.length,
                itemBuilder: (context, index) {
                  return Container(
                    padding: const EdgeInsets.only(
                      left: 16,
                      right: 16,
                    ),
                    child: getExcelFileItem(controller.excelFiles[index]),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget getExcelFileItem(ExcelFileModel excelFile) {
    return GetBuilder<ExcelToCsvController>(
      id: excelFile.name,
      builder: (controller) {
        return Card(
          child: Container(
            padding:
                const EdgeInsets.only(left: 16, right: 16, top: 8, bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                Text(excelFile.name, style: AppTextTheme.textStyle.body),
                Text(excelFile.convertStatus.value.text,
                    style: AppTextTheme.textStyle.hint),
              ],
            ),
          ),
        );
      },
    );
  }
}
