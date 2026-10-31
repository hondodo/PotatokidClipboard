import 'package:get/get.dart';
import 'package:potatokid_clipboard/user/model/user_model.dart';

class UserService extends GetxService {
  final Rx<UserModel> user = UserModel().obs;

  bool get hasLogin => user.value.isLogin;
  bool get isNotLogin => user.value.isNotLogin;

  @override
  void onInit() {
    super.onInit();
    clear();
  }

  @override
  void onClose() {
    super.onClose();
    clear();
  }

  void clear() {
    user.value = UserModel();
  }

  void setUser(UserModel user) {
    this.user.value = user;
  }
}
