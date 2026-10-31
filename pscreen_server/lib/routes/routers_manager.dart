import 'package:app_translator_web/pages/home/home_page.dart';
import 'package:app_translator_web/pages/home/vm/home_controller.dart';
import 'package:app_translator_web/pages/modify_translation/modify_translation_page.dart';
import 'package:app_translator_web/pages/note/note_page.dart';
import 'package:app_translator_web/pages/upload/upload_page.dart';
import 'package:app_translator_web/pages/upload_translation/upload_translation_page.dart';
import 'package:app_translator_web/pages/user_profile/user_profile_page.dart';
import 'package:app_translator_web/pages/user_profile/vm/user_profile_controller.dart';
import 'package:app_translator_web/pages/view_upload/view_upload_page.dart';
import 'package:app_translator_web/pages/weather/vm/weather_controller.dart';
import 'package:app_translator_web/pages/weather/vm/weather_page.dart';
import 'package:app_translator_web/routes/router_names.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

abstract class RouterManager {
  static final Map<String, Widget Function(BuildContext)> routes = {
    RouterNames.root: (context) {
      Get.lazyPut(() => HomeController());
      return const HomePage();
    },
    RouterNames.upload: (context) => const UploadPage(),
    RouterNames.files: (context) => const ViewUploadPage(),
    RouterNames.notes: (context) => const NotePage(),
    RouterNames.uploadTranslation: (context) => const UploadTranslationPage(),
    RouterNames.modifyTranslation: (context) => const ModifyTranslationPage(),
    RouterNames.userInfo: (context) {
      Get.lazyPut(() => UserProfileController());
      return const UserProfilePage();
    },
    RouterNames.weather: (context) {
      Get.lazyPut(() => WeatherController());
      return WeatherPage();
    },
  };

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
