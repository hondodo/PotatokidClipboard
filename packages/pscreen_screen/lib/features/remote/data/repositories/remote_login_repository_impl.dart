import 'package:pscreen_screen/app/config/app_config.dart';
import 'package:pscreen_screen/core/network/realtime_channel.dart';
import 'package:pscreen_screen/core/utils/app_settings.dart';
import 'package:pscreen_screen/features/remote/domain/repositories/remote_login_repository.dart';

/// [RemoteLoginRepository] 实现：封装 RealtimeChannel（WebSocket）与 AppSettings（账号持久化）。
class RemoteLoginRepositoryImpl implements RemoteLoginRepository {
  RemoteLoginRepositoryImpl({required RealtimeChannel channel})
      : _channel = channel;

  final RealtimeChannel _channel;

  @override
  String get savedAccount => AppSettings.instance.remoteAccount;

  @override
  Stream<RealtimeConnectionState> get onConnectionState =>
      _channel.connectionState;

  @override
  Stream<String> get onFatalError => _channel.fatalErrors;

  /// 确保 [AppSettings] 已加载（DI 注册时 await，保证 [savedAccount] 可信）。
  Future<void> ensureLoaded() => AppSettings.instance.ensureLoaded();

  @override
  Future<void> autoLogin() async {
    final String account = savedAccount;
    if (account.isEmpty) return;
    await _connect(account);
  }

  @override
  Future<void> switchAccount(String account) async {
    // 先持久化：连接失败时重启后仍重试该账号。
    await AppSettings.instance.setRemoteAccount(account);
    await _channel.disconnect();
    await _connect(account);
  }

  Future<void> _connect(String account) async {
    try {
      await _channel.connect(
        account: account,
        token: AppConfig.realtimeToken,
        role: 'tv',
      );
    } on RealtimeException catch (e) {
      throw RemoteLoginException(e.code, e.message);
    }
  }
}
