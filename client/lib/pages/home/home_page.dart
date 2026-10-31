import 'dart:io';

import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:potatokid_clipboard/app/app_enums.dart';
import 'package:potatokid_clipboard/framework/base/base_stateless_underline_bar_widget.dart';
import 'package:potatokid_clipboard/framework/components/navigations/navigation_widget.dart';
import 'package:potatokid_clipboard/framework/theme/app_text_theme.dart';
import 'package:potatokid_clipboard/pages/home/controller/home_controller.dart';
import 'package:potatokid_clipboard/pages/home/tabs/clipboard/clipboard_page.dart';
import 'package:potatokid_clipboard/pages/home/tabs/files/file_page.dart';
import 'package:potatokid_clipboard/pages/home/tabs/me/me_page.dart';
import 'package:potatokid_clipboard/pages/home/tabs/settings/settings_page.dart';
import 'package:potatokid_clipboard/pages/tools/tools_page.dart';
import 'package:potatokid_clipboard/user/widget/user_login_widget.dart';
import 'package:potatokid_clipboard/utils/device_utils.dart';

class HomePage extends BaseStatelessUnderlineBarWidget<HomeController> {
  const HomePage({super.key});

  @override
  String getTitle() {
    return '薯仔的剪贴板'.tr;
  }

  @override
  List<Widget>? buildActions() {
    return [
      const UserLoginWidget(),
      if (DeviceUtils.instance.isDesktop() && !Platform.isMacOS) ...[
        const SizedBox(width: 8),
        CloseWindowButton(
          onPressed: () {
            appWindow.minimize();
            Future.delayed(const Duration(milliseconds: 100), () {
              appWindow.hide();
            });
          },
        ),
      ],
      const SizedBox(width: 8),
    ];
  }

  @override
  PreferredSizeWidget? buildAppBar(BuildContext context) {
    return NavigationWidget(
      title: getTitle(),
      titleWidget: Row(
        children: [
          const SizedBox(width: 8),
          const Icon(Icons.paste),
          const SizedBox(width: 8),
          Expanded(
              child: Text(
            getTitle(),
            style: AppTextTheme.textStyle.title,
            overflow: TextOverflow.ellipsis,
          )),
        ],
      ),
      noBackLeading: true,
      onBack: onBack,
      backgroundColor: barBackgroundColor,
      foregroundColor: barForegroundColor,
      titleSpacing: 0,
      actions: buildActions(),
    );
  }

  @override
  Widget buildBody(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: TabBarView(
            controller: controller.tabController,
            children: controller.tabs.map(getTabBarView).toList(),
          ),
        ),
        TabBar(
          controller: controller.tabController,
          tabs: controller.tabs.map(getTabBar).toList(),
        ),
      ],
    );
  }

  Widget getTabBar(AppPage appPage) {
    switch (appPage) {
      case AppPage.clipboard:
        return Tab(text: '剪贴板'.tr);
      case AppPage.me:
        return Tab(text: '我的'.tr);
      case AppPage.settings:
        return Tab(text: '设置'.tr);
      case AppPage.files:
        return Tab(text: '文件'.tr);
      case AppPage.tools:
        return Tab(text: '工具'.tr);
    }
  }

  Widget getTabBarView(AppPage appPage) {
    switch (appPage) {
      case AppPage.clipboard:
        return const ClipboardPage();
      case AppPage.me:
        return const MePage();
      case AppPage.settings:
        return const SettingsPage();
      case AppPage.files:
        return const FilePage();
      case AppPage.tools:
        return const ToolsPage();
    }
  }
}
