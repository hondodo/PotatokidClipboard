import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:potatokid_clipboard/framework/base/base_get_vm.dart';
import 'package:potatokid_clipboard/services/login_service.dart';
import 'package:potatokid_clipboard/user/repository/user_repository.dart';
import 'package:potatokid_clipboard/utils/dialog_helper.dart';
import 'package:potatokid_clipboard/utils/error_utils.dart';

class LoginController extends BaseGetVM {
  final formKey = GlobalKey<FormState>();
  final usernameController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();
  final isLoading = false.obs;
  final isRegisterMode = false.obs;
  final userRepository = Get.put(UserRepository());

  @override
  void onInit() {
    super.onInit();
    var args = Get.arguments;
    if (args is Map<String, dynamic> && args['isRegisterMode'] != null) {
      var isRegisterModeArg = args['isRegisterMode'];
      if (isRegisterModeArg is bool) {
        isRegisterMode.value = isRegisterModeArg;
      }
    }
  }

  Future<void> register() async {
    if (!formKey.currentState!.validate()) {
      return;
    }

    isLoading.value = true;

    try {} catch (e) {
      DialogHelper.showTextToast('网络错误，请检查网络连接'.tr);
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> login() async {
    if (!formKey.currentState!.validate()) {
      return;
    }

    var username = usernameController.text.trim();
    if (username.isEmpty) {
      DialogHelper.showTextToast('请输入用户名'.tr);
      return;
    }

    var password = passwordController.text.trim();
    if (password.isEmpty) {
      DialogHelper.showTextToast('请输入密码'.tr);
      return;
    }

    try {
      DialogHelper.showTextLoading(text: '登录中...'.tr);
      bool isSuccess = await Get.find<LoginService>().login(username, password);
      if (!isSuccess) {
        DialogHelper.showTextToast('登录失败'.tr);
        return;
      }
      isLoading.value = true;
      Get.back();
      DialogHelper.showTextToast('登录成功'.tr);
    } catch (e) {
      ErrorUtils.showErrorToast(e);
    } finally {
      isLoading.value = false;
      DialogHelper.dismiss();
    }
  }
}
