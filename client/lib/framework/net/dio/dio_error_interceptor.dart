// import 'package:dio/dio.dart';
// import 'package:mystic/config/app_constants.dart';
// import 'package:mystic/utils/dialog_helper.dart';

//
// 
// MARK: 在DioManager里处理； ErrorUtils.showErrorToast(e);
// 在DioManager里处理； ErrorUtils.showErrorToast(e);
// 在DioManager里处理； ErrorUtils.showErrorToast(e);
//
//

// // 在DioManager里处理； ErrorUtils.showErrorToast(e);
// class DioErrorInterceptor extends Interceptor {
//   @override
//   void onError(DioException err, ErrorInterceptorHandler handler) {
//     switch (err.type) {
//       case DioExceptionType.connectionError: // 网络连接错误
//         DialogHelperCustom.showTextToast(
//             AppConstants.NOT_AUTHORIZED_NETWORK_CONNECT_FAILED);
//         break;
//       case DioExceptionType.connectionTimeout: // 网络超时
//         DialogHelperCustom.showTextToast(
//             AppConstants.NOT_AUTHORIZED_CONNECTION_TIME_OUT);
//         break;
//       default:
//         if (err.response != null) {
//           switch (err.response?.statusCode) {
//             case 403: // 服务器已经理解了请求，但是拒绝执行该请求
//               DialogHelper.dismiss();
//               // TODO:
//               // if (err.response?.data[AppConstants.NOT_AUTHORIZED_DETAIL] ==
//               //             AppConstants.NOT_AUTHENTICATED &&
//               //         err.response?.realUri != null
//               //     ? !err.response!.realUri
//               //         .toString()
//               //         .contains(HttpApiUrl.autoLoginApi)
//               //     : true) {
//               //   try {
//               //     Get.until((route) => route.isFirst);
//               //     Get.toNamed(Routes.loginMain);
//               //   } catch (e) {
//               //     e.printError();
//               //   }
//               // }
//               break;
//             default:
//               // DialogManager.showTextToast(
//               //     AppConstants.NOT_AUTHORIZED_UNKNOWN_ERROR); // 其他:发生未知错误
//               break;
//           }
//         }
//     }
//     super.onError(err, handler);
//   }
// }
