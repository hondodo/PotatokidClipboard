import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:potatokid_clipboard/app/app_enums.dart';
import 'package:potatokid_clipboard/framework/base/base_get_vm.dart';

class ToolsController extends BaseGetVM with GetSingleTickerProviderStateMixin {
  final RxList<ToolsTab> tabs = <ToolsTab>[].obs;
  late final TabController tabController;

  @override
  void onInit() {
    super.onInit();
    tabs.add(ToolsTab.timeStamp);
    tabs.add(ToolsTab.searchWeb);
    tabs.add(ToolsTab.excelToCsv);
    tabController = TabController(length: tabs.length, vsync: this);
  }
}
