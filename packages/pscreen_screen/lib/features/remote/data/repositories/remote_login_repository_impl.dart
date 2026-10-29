import 'package:pscreen_screen/core/network/realtime_channel.dart';
import 'package:pscreen_screen/core/utils/app_settings.dart';
import 'package:pscreen_screen/core/utils/client_info.dart';
import 'package:pscreen_screen/core/utils/device_credentials.dart';
import 'package:pscreen_screen/core/utils/ptools_util.dart';
import 'package:pscreen_screen/features/remote/domain/repositories/remote_login_repository.dart';

/// [RemoteLoginRepository] 实现：封装 RealtimeChannel（WebSocket）与 AppSettings（账号持久化）。
///
/// ws 握手与 HTTP `/api/login` 使用同一组凭据（账号 + 口令 MD5），
/// 服务端按 `datas/register/users/<账号>` 统一校验，故连接前先走一次
/// HTTP 登录（完成账号自动建档），再发起 ws 连接。
/// 握手同时携带 app/version/build（见 [ClientInfo]），供服务端区分控制端。
class RemoteLoginRepositoryImpl implements RemoteLoginRepository {
  RemoteLoginRepositoryImpl({
    required RealtimeChannel channel,
    Future<bool> Function()? httpLogin,
    Future<ClientInfo> Function()? clientInfo,
  })  : _channel = channel,
        _httpLogin = httpLogin ?? PtoolsUtil.loginWithSaved,
        _clientInfo = clientInfo ?? ClientInfo.current;

  final RealtimeChannel _channel;

  /// 连接前的 HTTP 预登录；测试注入假实现。
  final Future<bool> Function() _httpLogin;

  /// 客户端标识（包名/版本/构建号）读取；测试注入假实现。
  final Future<ClientInfo> Function() _clientInfo;

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
    final String account = await DeviceCredentials.account();
    if (account.isEmpty) return;
    await _connect(account);
  }

  @override
  Future<void> switchAccount(String account) async {
    // 先持久化：连接失败时重启后重试该账号（空串 = 回落设备号）。
    await AppSettings.instance.setRemoteAccount(account.trim());
    await _channel.disconnect();
    final String effective = await DeviceCredentials.account();
    if (effective.isEmpty) return;
    await _connect(effective);
  }

  Future<void> _connect(String account) async {
    // 先走一次 HTTP 登录：账号不存在时服务端按默认口令自动建档，
    // 否则 ws 握手会因「账号不存在」被拒（4001）。
    try {
      await _httpLogin();
    } catch (_) {
      // 登录失败不阻断：ws 侧仍有独立报错（4001），交由上层提示。
    }
    try {
      final ClientInfo info = await _clientInfo();
      await _channel.connect(
        account: account,
        token: DeviceCredentials.passwordMd5(),
        deviceId: await DeviceCredentials.deviceId(),
        role: 'tv',
        // 目标设备类型：电视（服务端在 roster/presence 回显，控制端据此选面板）。
        kind: 'tv',
        app: info.app,
        version: info.version,
        build: info.build,
      );
    } on RealtimeException catch (e) {
      throw RemoteLoginException(e.code, e.message);
    }
  }
}
