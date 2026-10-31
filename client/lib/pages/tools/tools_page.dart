import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:potatokid_clipboard/app/app_enums.dart';
import 'package:potatokid_clipboard/framework/base/base_stateless_sub_widget.dart';
import 'package:potatokid_clipboard/pages/tools/calc/calc_page.dart';
import 'package:potatokid_clipboard/pages/tools/calc/vm/calc_controller.dart';
import 'package:potatokid_clipboard/pages/tools/excel_to_csv/excel_to_csv_page.dart';
import 'package:potatokid_clipboard/pages/tools/excel_to_csv/vm/excel_to_csv_controller.dart';
import 'package:potatokid_clipboard/pages/tools/search_web/search_web_page.dart';
import 'package:potatokid_clipboard/pages/tools/search_web/vm/search_web_controller.dart';
import 'package:potatokid_clipboard/pages/tools/time_stamp/time_stamp_page.dart';
import 'package:potatokid_clipboard/pages/tools/time_stamp/vm/time_stamp_controller.dart';
import 'package:potatokid_clipboard/pages/tools/vm/tools_controller.dart';

class ToolsPage extends BaseStatelessSubWidget<ToolsController> {
  const ToolsPage({super.key});

  @override
  Widget buildBody(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 32,
          child: TabBar(
            isScrollable: true,
            padding: EdgeInsets.zero,
            labelPadding: EdgeInsets.symmetric(horizontal: 8),
            indicatorPadding: EdgeInsets.zero,
            tabAlignment: TabAlignment.start,
            controller: controller.tabController,
            tabs: controller.tabs.map(getTabBar).toList(),
          ),
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

  Widget getTabBar(ToolsTab toolsTab) {
    return Tab(
      text: toolsTab.text,
      height: 32,
    );
  }

  Widget getTabBarView(ToolsTab toolsTab) {
    switch (toolsTab) {
      case ToolsTab.excelToCsv:
        Get.lazyPut(() => ExcelToCsvController());
        return const ExcelToCsvPage();
      case ToolsTab.timeStamp:
        Get.lazyPut(() => TimeStampController());
        return const TimeStampPage();
      case ToolsTab.searchWeb:
        Get.lazyPut(() => SearchWebController());
        return const SearchWebPage();
      case ToolsTab.calc:
        Get.lazyPut(() => CalcController());
        return const CalcPage();
      case ToolsTab.none:
        return const SizedBox.shrink();
    }
  }
}
