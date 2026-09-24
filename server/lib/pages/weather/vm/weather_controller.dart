import 'dart:convert';

// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'package:app_translator_web/app/app_const.dart';
import 'package:app_translator_web/framework/base/base_get_vm.dart';
import 'package:app_translator_web/apis.dart';
import 'package:app_translator_web/pages/weather/model/ip_model.dart';
import 'package:get/get.dart';

class WeatherController extends BaseGetVM {
  final Rx<IpModel?> ipInfo = Rx<IpModel?>(null);

  @override
  void onInit() {
    super.onInit();
    getIpInfo().responseWithStatus(this);
  }

  Future<void> getIpInfo() async {
    final response = await html.HttpRequest.getString(Apis.getIpInfoUrl);
    final data = json.decode(response);
    if (data[AppConst.CODE] == AppConst.CODE_SUCCESS) {
      ipInfo.value = IpModel.fromJson(data[AppConst.DATA]);
    } else {
      throw Exception(data[AppConst.MSG]);
    }
  }
}
