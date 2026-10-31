import 'package:potatokid_clipboard/app/apis.dart';
import 'package:potatokid_clipboard/framework/mixin/default_http_request.dart';
import 'package:potatokid_clipboard/framework/net/mixin/request_mixin.dart';
import 'package:potatokid_clipboard/pages/home/tabs/me/model/ip_model.dart';

class MeRepository with RequestMixin {
  Future<IpModel> getIpInfo() async {
    final response = await Apis.getIpInfo.inBaseHost
        .getHttpRequestWithApi()
        .sendDataRequest(this);
    return IpModel.fromJson(response);
  }
}
