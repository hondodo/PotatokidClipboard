import 'dart:convert';

import 'package:get/get.dart';
import 'package:potatokid_clipboard/framework/app/app_exceptions.dart';
import 'package:potatokid_clipboard/framework/net/http_base_request.dart';
import 'package:potatokid_clipboard/framework/net/net_config.dart';
import 'package:potatokid_clipboard/framework/net/network_helper.dart';

final List<RESTResultFormat> _checkRESTList = [
  // 如果code相同，请在handleResult里根据url特殊处理
  RESTResultFormat(NetConfig.CODE, NetConfig.MSG, NetConfig.DATA, 0), // 默认
  RESTResultFormat('success', 'msg', 'data', 1), // 第三方接口;;消息的未知，暂用data
];

class RESTObj {
  final int code;
  final dynamic message;
  final dynamic data;
  // 如果code相同，请在handleResult里根据url特殊处理
  RESTObj({this.code = -1, this.message = '', this.data});
  factory RESTObj.fromJson(dynamic json) {
    var jsonObj = json;
    if (jsonObj is String) {
      jsonObj = jsonDecode(jsonObj);
    }

    if (jsonObj is Map<String, dynamic>) {
      for (var rest in _checkRESTList) {
        if (jsonObj.containsKey(rest.codeKey)) {
          var code = jsonObj[rest.codeKey];
          if (code == rest.successValue) {
            return RESTObj(
                code: 0,
                message: jsonObj[rest.msgKey],
                data: jsonObj[rest.dataKey]);
          }
          return RESTObj(
              code: code == 0 ? 1 : code,
              message: jsonObj[rest.msgKey],
              data: jsonObj[rest.dataKey]);
        }
      }
    }

    return RESTObj();
  }
}

mixin RequestMixin {
  // CancelToken cancelToken = CancelToken();

  // MARK: - 统一调用
  // 注：ContentNotJsonException 为原始返回的response内容
  // tipError = false 时，如果是dio错误仍会提示
  Future<dynamic> sendDataRequest(HttpBaseRequest request,
      {bool tipError = true, int maxRetry = 3}) async {
    // 先检测系统网络是否断开
    if (await NetworkHelper.isNetworkDisconnected()) {
      throw NetDisconnectException();
    }

    dynamic response =
        await request.send(maxRetry, contentType: request.contentType());
    return handleResult(request.url(), response, request.isJson());
  }

  dynamic handleResult(String url, dynamic input, bool checkJson) {
    if (!checkJson) {
      return input;
    }
    dynamic result = input;
    result = jsonDecode(input);
    if (result is Map<String, dynamic>) {
      var restObj = RESTObj.fromJson(result);
      bool success = restObj.code == 0;

      // MARK: 传入了url,不符合预设的规则的返回格式在这里处理
      if (success) {
        // ?? liftalk 即使数据错误也返回了0，只能从data里判断
        if (restObj.data is Map<String, dynamic>) {
          success = (restObj.data as Map<String, dynamic>).isNotEmpty;
          var message = restObj.message;
          if (!success && message is String) {
            message = message.toLowerCase();
            if (message == 'suc' ||
                message.startsWith('success') ||
                message == 'ok') {
              success = true;
            }
          }
        }
      }
      if (!success) {
        String message = 'unknown error'.tr;
        if (restObj.message is String) {
          message = restObj.message;
        } else if (restObj.message != null) {
          message = '${restObj.message}';
        }
        throw RESTCodeException(
            restObj.code == 0 ? -1 : restObj.code, message, restObj.data);
      }
      return restObj.data; // input[AppConstants.DATA];
    }
    throw ContentNotJsonException(result);
  }
}
