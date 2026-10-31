import 'package:get/get.dart';
import 'package:potatokid_clipboard/framework/utils/string_utils.dart';
import 'package:potatokid_clipboard/user/repository/user_repository.dart';
import 'package:potatokid_clipboard/user/user_service.dart';

class LoginService extends GetxService {
  UserRepository get userRepository => Get.find<UserRepository>();
  UserService get userService => Get.find<UserService>();

  Future<bool> login(String username, String password) async {
    var userModel = await userRepository.login(username, password.toMd5);
    if (userModel.isEmpty) {
      return false;
    }
    userService.setUser(userModel);
    return true;
  }
}
