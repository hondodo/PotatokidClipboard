import 'package:flutter/foundation.dart';

/// 远程登录状态（对应「远程」行五种展示文案）。
enum RemoteLoginStatus {
  /// 未设置账号。
  notConfigured,

  /// 正在登录。
  loggingIn,

  /// 登录成功、数据同步中。
  syncing,

  /// 登录成功且主数据同步完成。
  loggedIn,

  /// 登录失败 / 被踢下线。
  error,
}

/// 远程登录状态机的不可变 State。
@immutable
class RemoteLoginState {
  const RemoteLoginState({
    required this.account,
    required this.status,
    this.errorMessage,
  });

  /// 已配置的云信账号（空串表示未设置）。
  final String account;

  /// 当前登录状态。
  final RemoteLoginStatus status;

  /// error 态详情（日志/调试用）。
  final String? errorMessage;

  /// 由持久化账号构造初始态：空 → 未设置；非空 → 正在登录（autoLogin 随即派发）。
  factory RemoteLoginState.fromAccount(String account) => RemoteLoginState(
        account: account,
        status: account.isEmpty
            ? RemoteLoginStatus.notConfigured
            : RemoteLoginStatus.loggingIn,
      );

  RemoteLoginState copyWith({
    String? account,
    RemoteLoginStatus? status,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) =>
      RemoteLoginState(
        account: account ?? this.account,
        status: status ?? this.status,
        errorMessage:
            clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RemoteLoginState &&
          other.account == account &&
          other.status == status &&
          other.errorMessage == errorMessage);

  @override
  int get hashCode => Object.hash(account, status, errorMessage);
}
