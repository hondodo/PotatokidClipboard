import 'dart:async';

import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:potatokid_clipboard/app/app_enums.dart';
import 'package:potatokid_clipboard/framework/base/base_get_vm.dart';
import 'package:potatokid_clipboard/services/steam_service.dart';
import 'package:potatokid_clipboard/utils/device_utils.dart';
import 'package:potatokid_clipboard/utils/service_tools_utils.dart';
import 'package:potatokid_clipboard/utils/try_icon_helper.dart';

class HomeController extends BaseGetVM with GetSingleTickerProviderStateMixin {
  RxList<AppPage> tabs = <AppPage>[].obs;
  late final TabController tabController;
  late StreamSubscription<AppPage> homePageStreamSubscription;

  @override
  void onInit() {
    super.onInit();
    tabs.add(AppPage.clipboard);
    tabs.add(AppPage.files);
    tabs.add(AppPage.tools);
    tabs.add(AppPage.me);
    tabs.add(AppPage.settings);
    tabController = TabController(length: tabs.length, vsync: this);
    homePageStreamSubscription = ServiceToolsUtils
        .instance.steamService.homePageStream
        .listen(onTabChangedRequest);
    TryIconHelper.setUpTray();
    if (!DeviceUtils.instance.isMobile()) {
      appWindow.title = '薯仔工具箱-剪贴板'.tr;
    }
  }

  @override
  void onClose() {
    homePageStreamSubscription.cancel();
    super.onClose();
  }

  void onTabChangedRequest(AppPage appPage) {
    tabController.animateTo(tabs.indexOf(appPage));
  }
}
