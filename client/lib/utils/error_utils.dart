import 'package:dio/dio.dart';
import 'package:get/get.dart';
import 'package:potatokid_clipboard/framework/app/app_exceptions.dart';
import 'package:potatokid_clipboard/utils/dialog_helper.dart';

class ErrorUtils {
  static dynamic showErrorToast(dynamic e, {bool tipError = true}) {
    if (e is NetDisconnectException) {
      if (tipError) {
        DialogHelper.showTextToast('网络连接失败'.tr);
      }
      return true;
    }
    if (e is Map && e.containsKey('error')) {
      if (tipError) {
        DialogHelper.showTextToast(e['error'].toString());
      }
      return true;
    } else if (e is RESTCodeException && e.message != null) {
      String message = e.message ?? '发生未知错误'.tr;

      if (tipError) {
        DialogHelper.showTextToast(message);
      }
      return true;
    } else if (e is DioException) {
      switch (e.type) {
        case DioExceptionType.connectionError: // 网络连接错误
          if (tipError) {
            DialogHelper.showTextToast('网络连接失败，请检查网络连接'.tr);
          }
          return true;
        case DioExceptionType.connectionTimeout: // 网络超时
          if (tipError) {
            DialogHelper.showTextToast('网络超时，请检查网络连接'.tr);
          }
          return true;
        default:
          if (e.response != null) {
            int code = e.response?.statusCode ?? -1;
            DialogHelper.showTextToast(
                '网络错误，请检查网络连接，代码：@code'.trParams({'code': code.toString()}));
          }
      }
    } else if (e is String) {
      if (tipError) {
        DialogHelper.showTextToast(e);
      }
    } else {
      if (tipError) {
        DialogHelper.showTextToast('发生未知错误，请稍后再试'.tr);
      }
    }
    return null;
  }
}
