import 'package:potatokid_clipboard/app/apis.dart';
import 'package:potatokid_clipboard/framework/mixin/default_http_request.dart';
import 'package:potatokid_clipboard/framework/net/http_base_request.dart';
import 'package:potatokid_clipboard/framework/net/mixin/request_mixin.dart';
import 'package:potatokid_clipboard/user/model/user_model.dart';

class UserRepository with RequestMixin {
  Future<UserModel> login(String username, String passwordMd5) async {
    final response = await Apis.login.inBaseHost.getHttpRequestWithApi(
      params: {
        'username': username,
        'password': passwordMd5,
      },
      httpMethod: HttpMethod.POST,
    ).sendDataRequest(this);
    return UserModel.fromJson(response['user']);
  }

  Future<UserModel> autoLogin() async {
    final response = await Apis.autoLogin.inBaseHost
        .getHttpRequestWithApi(
          httpMethod: HttpMethod.POST,
        )
        .sendDataRequest(this);
    return UserModel.fromJson(response['user']);
  }
}
