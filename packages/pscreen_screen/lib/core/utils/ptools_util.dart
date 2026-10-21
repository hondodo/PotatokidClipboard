import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:pscreen_screen/app/config/app_constants.dart';
import 'package:pscreen_screen/core/network/dio_manager.dart';
import 'package:pscreen_screen/core/network/http_method.dart';
import 'package:pscreen_screen/core/utils/app_settings.dart';

class PtoolsCode {
  const PtoolsCode._();

  static const int success = 0;
  static const int failed = 1;
  static const int unlogin = 100000;
  static const int userNotExists = 100001;
  static const int userPasswordError = 100002;
  static const int fileNotExists = 200000;
  static const int fileForbidden = 200001;
}

class PtoolsException implements Exception {
  const PtoolsException(this.code, this.message);

  final int code;
  final String message;

  bool get isUnlogin => code == PtoolsCode.unlogin;

  @override
  String toString() => 'PtoolsException(code: $code, message: $message)';
}

class PtoolsUtil {
  const PtoolsUtil._();

  static Future<void> login({
    required String username,
    required String password,
  }) async {
    final String account = username.trim();
    if (account.isEmpty || password.isEmpty) {
      throw const PtoolsException(PtoolsCode.failed, '账号和密码不能为空');
    }

    final dynamic data = await DioManager().send(
      url: AppConstants.ptoolsLoginUrl,
      method: HttpMethod.POST,
      params: <String, dynamic>{
        'username': account,
        'password': md5.convert(utf8.encode(password)).toString(),
      },
      contentType: 'application/json',
      notTipNetError: true,
    );

    final Map<String, dynamic>? map = _asMap(data);
    if (map == null) {
      throw const PtoolsException(PtoolsCode.failed, '登录响应格式错误');
    }
    final int code = _intOf(map['code']);
    if (code != PtoolsCode.success) {
      throw PtoolsException(code, '${map['msg'] ?? '登录失败'}');
    }
  }

  /// 正在进行的「用已保存凭据登录」；并发调用共享同一次，避免同一批拉取
  /// 同时命中未登录时重复请求登录接口。
  static Future<bool>? _loginInFlight;

  /// 用「我的」页保存的 Tools 账号/密码登录；未配置或失败返回 false。
  static Future<bool> loginWithSaved() {
    return _loginInFlight ??= _doLoginWithSaved().whenComplete(() {
      _loginInFlight = null;
    });
  }

  static Future<bool> _doLoginWithSaved() async {
    await AppSettings.instance.ensureLoaded();
    final String account = AppSettings.instance.toolsAccount;
    final String password = AppSettings.instance.toolsPassword;
    if (account.isEmpty || password.isEmpty) return false;
    try {
      await login(username: account, password: password);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<String> fetchScreenFile(
    String filename, {
    bool retryOnUnlogin = true,
  }) =>
      fetchUrl(
        '${AppConstants.githubDataBaseUrl}$filename',
        retryOnUnlogin: retryOnUnlogin,
      );

  /// 取 [url] 的纯文本内容；遇到「未登录」错误时自动用已保存凭据重登一次再取。
  ///
  /// 可透传单请求的超时与重试次数，便于批量同步（如 [DataFiles]）按文件限时。
  static Future<String> fetchUrl(
    String url, {
    bool retryOnUnlogin = true,
    int maxRetry = AppConstants.defaultMaxRetry,
    Duration? connectTimeout,
    Duration? receiveTimeout,
  }) async {
    final String text = await _getPlain(
      url,
      maxRetry: maxRetry,
      connectTimeout: connectTimeout,
      receiveTimeout: receiveTimeout,
    );
    final PtoolsException? error = _parseError(text);
    if (error == null) return text;
    if (error.isUnlogin && retryOnUnlogin) {
      if (await loginWithSaved()) {
        return fetchUrl(
          url,
          retryOnUnlogin: false,
          maxRetry: maxRetry,
          connectTimeout: connectTimeout,
          receiveTimeout: receiveTimeout,
        );
      }
    }
    throw error;
  }

  static Future<String> _getPlain(
    String url, {
    int maxRetry = AppConstants.defaultMaxRetry,
    Duration? connectTimeout,
    Duration? receiveTimeout,
  }) async {
    final dynamic data = await DioManager().send(
      url: url,
      responseType: ResponseType.plain,
      notTipNetError: true,
      maxRetry: maxRetry,
      connectTimeout: connectTimeout,
      receiveTimeout: receiveTimeout,
    );
    return data is String ? data : '';
  }

  static PtoolsException? _parseError(String text) {
    final String trimmed = text.trim();
    if (!trimmed.startsWith('{') || !trimmed.contains('"code"')) return null;
    try {
      final Map<String, dynamic>? map = _asMap(jsonDecode(trimmed));
      if (map == null) return null;
      final int code = _intOf(map['code']);
      if (code == PtoolsCode.success) return null;
      return PtoolsException(code, '${map['msg'] ?? '请求失败'}');
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic>? _asMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return null;
  }

  static int _intOf(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? -1;
  }
}
