import 'package:get/get.dart';
import 'package:potatokid_clipboard/services/login_service.dart';
import 'package:potatokid_clipboard/services/page_service.dart';
import 'package:potatokid_clipboard/services/steam_service.dart';
import 'package:potatokid_clipboard/user/user_service.dart';

class ServiceToolsUtils {
  static final ServiceToolsUtils _instance = ServiceToolsUtils._();
  ServiceToolsUtils._();
  static ServiceToolsUtils get instance => _instance;

  SteamService get steamService => Get.find<SteamService>();
  PageService get pageService => Get.find<PageService>();
  LoginService get loginService => Get.find<LoginService>();
  UserService get userService => Get.find<UserService>();
}
