import 'package:flutter/material.dart';
import 'package:get/get_state_manager/src/rx_flutter/rx_ticket_provider_mixin.dart';
import 'package:potatokid_clipboard/app/app_enums.dart';
import 'package:potatokid_clipboard/framework/base/base_get_vm.dart';

class FileController extends BaseGetVM with GetSingleTickerProviderStateMixin {
  late List<FileTab> tabs;
  late TabController tabController;

  @override
  void onInit() {
    super.onInit();
    tabs = [FileTab.upload, FileTab.download];
    tabController = TabController(length: tabs.length, vsync: this);
  }
}
