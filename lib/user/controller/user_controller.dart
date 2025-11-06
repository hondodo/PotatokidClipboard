import 'package:get/get.dart';
import 'package:potatokid_clipboard/app/app_enums.dart';
import 'package:potatokid_clipboard/framework/base/base_get_vm.dart';
import 'package:potatokid_clipboard/framework/net/dio/dio_manager.dart';
import 'package:potatokid_clipboard/framework/utils/app_log.dart';
import 'package:potatokid_clipboard/routes/router_names.dart';
import 'package:potatokid_clipboard/user/model/user_model.dart';
import 'package:potatokid_clipboard/user/repository/user_repository.dart';
import 'package:potatokid_clipboard/user/user_service.dart';
import 'package:potatokid_clipboard/utils/service_tools_utils.dart';

class UserController extends BaseGetVM {
  final UserRepository userRepository = Get.put(UserRepository());
  Rx<UserModel> get user => Get.find<UserService>().user;

  @override
  void onInit() {
    super.onInit();
    autoLogin();
  }

  Future<void> autoLogin() async {
    try {
      var userModel = await userRepository.autoLogin();
      if (userModel.isEmpty) {
        return;
      }
      Get.find<UserService>().setUser(userModel);
    } catch (e) {
      Log.e('UserController] 自动登录失败: $e');
    }
  }

  void showUserProfile() {
    ServiceToolsUtils.instance.steamService.homePageStreamController
        .add(AppPage.me);
  }

  void logout() {
    ServiceToolsUtils.instance.userService.clear();
    DioManager().clearCookie();
  }

  void showIpInfo() {
    ServiceToolsUtils.instance.steamService.homePageStreamController
        .add(AppPage.me);
  }

  void showLoginPage({bool isRegisterMode = false}) {
    Get.toNamed(RouterNames.login,
        arguments: {'isRegisterMode': isRegisterMode});
  }
}
