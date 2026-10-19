// ignore: depend_on_referenced_packages
import 'package:nim_core_v2_platform_interface/nim_core_v2_platform_interface.dart' hide Log;
import 'package:potatokid_screen/app/config/app_config.dart';
import 'package:potatokid_screen/core/utils/app_settings.dart';
import 'package:potatokid_screen/core/utils/nim_manager.dart';
import 'package:potatokid_screen/features/remote/domain/repositories/remote_login_repository.dart';

/// [RemoteLoginRepository] 实现：封装 NimManager（云信 SDK）与 AppSettings（账号持久化）。
class RemoteLoginRepositoryImpl implements RemoteLoginRepository {
  RemoteLoginRepositoryImpl({required NimManager nim}) : _nim = nim;

  final NimManager _nim;

  @override
  String get savedAccount => AppSettings.instance.nimAccount;

  @override
  Stream<NIMLoginStatus> get onLoginStatus => _nim.onLoginStatus;

  @override
  Stream<NIMDataSyncDetail> get onDataSync => _nim.onDataSync;

  @override
  Stream<NIMError> get onLoginFailed => _nim.onLoginFailed;

  @override
  Stream<NIMKickedOfflineDetail> get onKickedOffline => _nim.onKickedOffline;

  /// 确保 [AppSettings] 已加载（DI 注册时 await，保证 [savedAccount] 可信）。
  Future<void> ensureLoaded() => AppSettings.instance.ensureLoaded();

  @override
  Future<void> autoLogin() async {
    final String account = savedAccount;
    if (account.isEmpty) return;
    await _login(account);
  }

  @override
  Future<void> switchAccount(String account) async {
    // 先持久化：登录失败时重启后仍重试该账号。
    await AppSettings.instance.setNimAccount(account);
    final NIMResult<NIMLoginStatus> status = await _nim.getLoginStatus();
    final NIMLoginStatus? current = status.data;
    if (current == NIMLoginStatus.loginStatusLogined ||
        current == NIMLoginStatus.loginStatusLogining) {
      try {
        await _nim.logout();
      } catch (_) {
        // 登出失败忽略：随后的新登录会顶掉旧会话。
      }
    }
    await _login(account);
  }

  Future<void> _login(String account) async {
    final NIMResult<void> result =
        await _nim.login(accountId: account, token: AppConfig.nimPassword);
    if (!result.isSuccess) {
      throw RemoteLoginException(result.code, result.errorDetails);
    }
  }
}
