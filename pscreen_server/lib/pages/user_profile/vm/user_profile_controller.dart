import 'package:app_translator_web/app/app_const.dart';
import 'package:app_translator_web/framework/base/base_get_vm.dart';
import 'package:app_translator_web/apis.dart';
import 'package:app_translator_web/pages/weather/model/ip_model.dart';
import 'package:app_translator_web/utils/cookie_helper.dart';
import 'package:get/get.dart';

// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:convert';

class UserProfileController extends BaseGetVM {
  final Rx<IpModel?> locationData = Rx<IpModel?>(null);
  final Rx<String?> username = Rx<String?>(null);

  @override
  void onInit() {
    super.onInit();
    username.value = CookieHelper.getCookie('username');
    onRetry();
  }

  @override
  void onRetry() {
    super.onRetry();
    getIpInfo().responseWithStatus(this);
  }

  Future<void> getIpInfo() async {
    final response = await html.HttpRequest.getString(Apis.getIpInfoUrl);
    final data = json.decode(response);
    if (data[AppConst.CODE] == AppConst.CODE_SUCCESS) {
      locationData.value = IpModel.fromJson(data[AppConst.DATA]);
    } else {
      throw Exception(data[AppConst.MSG]);
    }
  }
}
