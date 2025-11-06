import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:potatokid_clipboard/pages/home/controller/home_controller.dart';
import 'package:potatokid_clipboard/pages/home/home_page.dart';
import 'package:potatokid_clipboard/pages/home/tabs/clipboard/vm/clipboard_controller.dart';
import 'package:potatokid_clipboard/pages/home/tabs/clipboard/repository/clipboard_repository.dart';
import 'package:potatokid_clipboard/pages/home/tabs/me/repository/me_repository.dart';
import 'package:potatokid_clipboard/pages/home/tabs/me/vm/me_controller.dart';
import 'package:potatokid_clipboard/pages/home/tabs/settings/controller/settings_controller.dart';
import 'package:potatokid_clipboard/pages/login/controller/login_controller.dart';
import 'package:potatokid_clipboard/pages/login/login_page.dart';
import 'package:potatokid_clipboard/routes/router_names.dart';
import 'package:potatokid_clipboard/user/controller/user_controller.dart';

abstract class RouterManager {
  static final Map<String, Widget Function(BuildContext)> routes = {
    RouterNames.root: (context) {
      Get.lazyPut(() => UserController());
      Get.lazyPut(() => HomeController());
      Get.lazyPut(() => ClipboardController());
      Get.lazyPut(() => MeController());
      Get.lazyPut(() => MeRepository());
      Get.lazyPut(() => ClipboardRepository());
      Get.lazyPut(() => SettingsController());
      return const HomePage();
    },
    RouterNames.login: (context) {
      Get.lazyPut(() => LoginController());
      return const LoginPage();
    },
  };
  // 使用getPages会出现按下F5刷新页面时，页面会重新加载，导致页面状态丢失
  // static final pages = [
  //   GetPage(
  //     name: RouterNames.root,
  //     page: () => const HomePage(),
  //     binding: BindingsBuilder(() {}),
  //   ),
  //   GetPage(
  //     name: RouterNames.upload,
  //     page: () => const UploadPage(),
  //     binding: BindingsBuilder(() {}),
  //   ),
  //   GetPage(
  //     name: RouterNames.files,
  //     page: () => const ViewUploadPage(),
  //     binding: BindingsBuilder(() {}),
  //   ),
  //   GetPage(
  //     name: RouterNames.notes,
  //     page: () => const NotePage(),
  //     binding: BindingsBuilder(() {}),
  //   ),
  //   GetPage(
  //     name: RouterNames.uploadTranslation,
  //     page: () => const UploadTranslationPage(),
  //     binding: BindingsBuilder(() {}),
  //   ),
  //   GetPage(
  //     name: RouterNames.modifyTranslation,
  //     page: () => const ModifyTranslationPage(),
  //     binding: BindingsBuilder(() {}),
  //   ),
  //   GetPage(
  //     name: RouterNames.userInfo,
  //     page: () => const UserProfilePage(),
  //     binding: BindingsBuilder(() {}),
  //   ),
  //   GetPage(
  //     name: RouterNames.weather,
  //     page: () => WeatherPage(),
  //     binding: BindingsBuilder(() {
  //       Get.lazyPut(() => WeatherController());
  //     }),
  //   ),
  // ];
}
