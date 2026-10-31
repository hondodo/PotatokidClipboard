import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:get/get.dart';
import 'package:potatokid_clipboard/app/app_enums.dart';
import 'package:potatokid_clipboard/framework/app/app_exceptions.dart';
import 'package:potatokid_clipboard/framework/base/base_get_vm.dart';
import 'package:potatokid_clipboard/framework/net/dio/dio_manager.dart';
import 'package:potatokid_clipboard/framework/utils/app_log.dart';
import 'package:potatokid_clipboard/routes/router_names.dart';
import 'package:potatokid_clipboard/user/model/user_model.dart';
import 'package:potatokid_clipboard/user/repository/user_repository.dart';
import 'package:potatokid_clipboard/user/user_service.dart';
import 'package:potatokid_clipboard/utils/service_tools_utils.dart';

class UserController extends BaseGetVM {
  final UserRepository userRepository = Get.put(UserRepository());
  Rx<UserModel> get user => Get.find<UserService>().user;

  Timer? _autoLoginRetryTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Worker? _userWorker;
  bool _autoLoginEnabled = false;
  bool _autoLoginInProgress = false;
  bool _isClosed = false;
  int _autoLoginRetryAttempt = 0;

  @override
  void onInit() {
    super.onInit();
    _userWorker = ever<UserModel>(user, (userModel) {
      if (userModel.isLogin) {
        _stopAutoLoginRetries();
      }
    });
    unawaited(_initializeAutoLogin());
  }

  Future<void> _initializeAutoLogin() async {
    bool hasUsernameCookie;
    try {
      hasUsernameCookie = await DioManager().hasCookie('username');
    } catch (e) {
      Log.e('UserController] 读取自动登录 Cookie 失败: $e');
      return;
    }
    if (_isClosed || !hasUsernameCookie || user.value.isLogin) return;

    _autoLoginEnabled = true;
    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen((results) {
      final isConnected =
          results.any((result) => result != ConnectivityResult.none);
      if (!isConnected || !_autoLoginEnabled || user.value.isLogin) return;

      _autoLoginRetryTimer?.cancel();
      _autoLoginRetryAttempt = 0;
      unawaited(_attemptAutoLogin());
    });
    await _attemptAutoLogin();
  }

  Future<void> _attemptAutoLogin() async {
    if (!_autoLoginEnabled ||
        _autoLoginInProgress ||
        _isClosed ||
        user.value.isLogin) {
      return;
    }

    _autoLoginRetryTimer?.cancel();
    _autoLoginInProgress = true;
    try {
      final userModel = await userRepository.autoLogin();
      if (_isClosed || !_autoLoginEnabled || user.value.isLogin) return;
      if (userModel.isEmpty) {
        _stopAutoLoginRetries();
        return;
      }
      Get.find<UserService>().setUser(userModel);
    } catch (e) {
      Log.e('UserController] 自动登录失败: $e');
      if (_isRetryableAutoLoginError(e)) {
        _scheduleAutoLoginRetry();
      } else {
        _stopAutoLoginRetries();
      }
    } finally {
      _autoLoginInProgress = false;
    }
  }

  bool _isRetryableAutoLoginError(Object error) {
    if (error is NetDisconnectException || error is TimeoutException) {
      return true;
    }
    if (error is HttpCodeException) {
      final statusCode = error.httpCode;
      return statusCode == null ||
          statusCode == 408 ||
          statusCode == 429 ||
          statusCode >= 500;
    }
    if (error is DioException) {
      final statusCode = error.response?.statusCode;
      if (statusCode != null) {
        return statusCode == 408 || statusCode == 429 || statusCode >= 500;
      }
      return error.type != DioExceptionType.cancel &&
          error.type != DioExceptionType.badCertificate;
    }
    return false;
  }

  void _scheduleAutoLoginRetry() {
    if (!_autoLoginEnabled || _isClosed || user.value.isLogin) return;

    const retryDelays = <Duration>[
      Duration(seconds: 5),
      Duration(seconds: 10),
      Duration(seconds: 20),
      Duration(seconds: 40),
      Duration(seconds: 60),
    ];
    final delayIndex = _autoLoginRetryAttempt < retryDelays.length
        ? _autoLoginRetryAttempt
        : retryDelays.length - 1;
    final delay = retryDelays[delayIndex];
    _autoLoginRetryAttempt++;
    _autoLoginRetryTimer?.cancel();
    _autoLoginRetryTimer = Timer(delay, () {
      unawaited(_attemptAutoLogin());
    });
    Log.i('UserController] 将在 ${delay.inSeconds} 秒后重试自动登录');
  }

  void _stopAutoLoginRetries() {
    _autoLoginEnabled = false;
    _autoLoginRetryTimer?.cancel();
    _autoLoginRetryTimer = null;
    unawaited(_connectivitySubscription?.cancel());
    _connectivitySubscription = null;
  }

  void showUserProfile() {
    ServiceToolsUtils.instance.steamService.homePageStreamController
        .add(AppPage.me);
  }

  Future<void> logout() async {
    _stopAutoLoginRetries();
    ServiceToolsUtils.instance.userService.clear();
    await DioManager().clearCookie();
  }

  void showIpInfo() {
    ServiceToolsUtils.instance.steamService.homePageStreamController
        .add(AppPage.me);
  }

  void showLoginPage({bool isRegisterMode = false}) {
    Get.toNamed(RouterNames.login,
        arguments: {'isRegisterMode': isRegisterMode});
  }

  @override
  void onClose() {
    _isClosed = true;
    _stopAutoLoginRetries();
    _userWorker?.dispose();
    super.onClose();
  }
}
