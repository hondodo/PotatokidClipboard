import '../../framework/app/app_exceptions.dart';
import '../../framework/mixin/base_status_mixin.dart';
import '../../framework/mixin/tip_overlay_mixin.dart';
import '../../framework/utils/app_log.dart';
import 'package:get/get.dart';

abstract class BaseGetVM extends GetxController
    with BaseStatusMixin, TipOverlayMixin {
  void setStatus(StatusContent statusContent) {
    status.value = statusContent;
  }
}

extension ExcptionExtensions on Exception {
  /// 数据解析错误、数据空白需要另行处理，此处返回 unknown, 取消、网络未连接、网络超时、404等
  StatusErrorCode toStatusErrorCode() {
    if (this is NetDisconnectException) {
      return StatusErrorCode.disconnect;
    } else if (this is HttpCodeException) {
      return StatusErrorCode.assectError;
    } else if (this is RESTCodeException) {
      return StatusErrorCode.dataError;
    } else if (this is ContentNotJsonException) {
      return StatusErrorCode.dataError;
    }
    return StatusErrorCode.unknown;
  }
}

extension FutureExtensions<T> on Future<T> {
  Future<T> responseWithStatus(BaseGetVM vm) {
    vm.setStatus(StatusContent.loading());
    return then((value) {
      vm.setStatus(StatusContent.success());
      return value;
    }).catchError((error) {
      Log.e('request net controller error: $error');
      if (error is TypeError) {
        vm.showError(error.toString());
      } else if (error is Exception) {
        var code = error.toStatusErrorCode();
        vm.setStatus(StatusContent.error(code));
      }
      vm.setStatus(StatusContent.error(StatusErrorCode.unknown));
      // 改为不抛出错误，如果后面接then  responseWithStatus(this).then()... 需要自行处理数据
      throw error;
    });
  }

  Future<T> ignoreError() {
    return catchError((error) {
      Log.e('ignoreError: $error');
    });
  }
}
