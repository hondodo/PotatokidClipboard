import 'package:flutter/material.dart';
import 'package:potatokid_clipboard/app/app_enums.dart';
import 'package:potatokid_clipboard/framework/base/base_stateless_sub_widget.dart';
import 'package:potatokid_clipboard/pages/home/tabs/files/controller/file_controller.dart';
import 'package:potatokid_clipboard/pages/home/tabs/files/file_download_page.dart';
import 'package:potatokid_clipboard/pages/home/tabs/files/file_upload_page.dart';

class FilePage extends BaseStatelessSubWidget<FileController> {
  const FilePage({super.key});

  @override
  Widget buildBody(BuildContext context) {
    return Column(
      children: [
        TabBar(
          tabs: controller.tabs.map(getTabBar).toList(),
          controller: controller.tabController,
        ),
        Expanded(
          child: TabBarView(
            controller: controller.tabController,
            children: controller.tabs.map(getTabBarView).toList(),
          ),
        ),
      ],
    );
  }

  Widget getTabBar(FileTab tab) {
    return Tab(text: tab.name);
  }

  Widget getTabBarView(FileTab tab) {
    switch (tab) {
      case FileTab.upload:
        return const FileUploadPage();
      case FileTab.download:
        return const FileDownloadPage();
    }
  }
}
