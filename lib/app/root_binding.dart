import 'package:get/get.dart';
import 'package:potatokid_clipboard/pages/home/tabs/clipboard/repository/clipboard_repository.dart';
import 'package:potatokid_clipboard/services/clipboard_service.dart';
import 'package:potatokid_clipboard/services/login_service.dart';
import 'package:potatokid_clipboard/services/page_service.dart';
import 'package:potatokid_clipboard/services/settings_service.dart';
import 'package:potatokid_clipboard/services/steam_service.dart';
import 'package:potatokid_clipboard/user/repository/user_repository.dart';
import 'package:potatokid_clipboard/user/user_service.dart';

/// 全局
class RootBinding extends Bindings {
  @override
  void dependencies() {
    Get.put(SteamService());
    Get.put(PageService());
    Get.put(LoginService());
    Get.put(UserService());
    Get.put(UserRepository());
    Get.put(ClipboardRepository());
    Get.put(ClipboardService());
    Get.put(SettingsService());
  }
}
