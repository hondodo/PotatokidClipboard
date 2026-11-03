import 'package:flutter/foundation.dart';
import 'package:pscreen_home/core/router/route_names.dart';
import 'package:pscreen_screen/app/config/app_constants.dart';
import 'package:pscreen_screen/core/network/dio_manager.dart';
import 'package:pscreen_screen/core/network/http_method.dart';
import 'package:pscreen_screen/core/utils/device_credentials.dart';

/// 当前登录账号的会话状态：保留 `/api/login` 响应中的 `user.role`。
///
/// 共享包 `PtoolsUtil.login` 只校验 `code`、丢弃响应体，而家长视图分流与
/// 解锁弹层注册都需要角色信息（方案 4.2「需先让 PtoolsUtil.login 保留
/// 响应中的 user.role」）；共享包不在本次改动范围内，因此中控端用同一组
/// 凭据、同一接口自行发起登录并解析 `data.user.role`，成功后记在
/// [roleNotifier] 上供路由分流与解锁弹层消费。
///
/// 三级角色（方案 4.2 定稿）：`admin` 超管/运维、`parent` 家长、`user`
/// 普通成员。服务端角色枚举扩展由服务端任务负责；客户端对缺失/未知值
/// 一律按 `user` 处理——最保守：无家长入口、不注册解锁弹层。
class AccountSession {
  AccountSession._();

  /// 角色变化通知（登录成功写入、账号切换且登录失败时清空）；
  /// 解锁弹层据此注册 / 注销 `events.listen`。
  static final ValueNotifier<String> roleNotifier = ValueNotifier<String>('');

  /// 进行中的登录：并发调用共享同一次请求（与 PtoolsUtil 口径一致）。
  static Future<bool>? _loginInFlight;

  /// 上一次成功登录的账号；仅当账号真正切换且新登录失败时才清空角色，
  /// 同账号的后台刷新登录不能把已有角色短暂清空。
  static String _roleAccount = '';

  /// 当前账号角色；未登录 / 登录失败时为空串（按 `user` 处理）。
  static String get role => roleNotifier.value;

  /// 是否家长能力持有者（家长视图 + 解锁弹层下发）。
  static bool get isParent => role == 'parent';

  static bool get isAdmin => role == 'admin';

  static bool get isParentOrAdmin => isParent || isAdmin;

  /// 登录分流：`parent` 默认进家长视图；`admin` / `user` 进现有中控台
  ///（现状没有独立 admin 视图，admin 走「现状 + 设置页家长视图入口」，
  ///  进入家长视图后放开 owner 过滤代管全部 TV，见方案 4.2 风险 #13）。
  static String initialHomePathFor(String homeRole) =>
      homeRole == 'parent' ? RouteNames.parentalPath : RouteNames.home;

  /// 用当前生效凭据登录（设置自定义 > `.env` > 设备号 + 默认口令），
  /// 成功后刷新 [role]。失败返回 false，不抛异常。
  static Future<bool> loginWithSaved() =>
      _loginInFlight ??= _doLogin().whenComplete(() {
        _loginInFlight = null;
      });

  static Future<bool> _doLogin() async {
    final String account = (await DeviceCredentials.account()).trim();
    final String passwordMd5 = DeviceCredentials.passwordMd5();
    if (account.isEmpty || passwordMd5.isEmpty) return false;
    final bool accountChanged =
        _roleAccount.isNotEmpty && account != _roleAccount;
    try {
      final dynamic data = await DioManager().send(
        url: AppConstants.ptoolsLoginUrl,
        method: HttpMethod.POST,
        params: <String, dynamic>{
          'username': account,
          'password': passwordMd5,
        },
        contentType: 'application/json',
        notTipNetError: true,
      );
      final Map<String, dynamic>? body = _asMap(data);
      if (body == null) {
        if (accountChanged) _clearRole();
        return false;
      }
      final dynamic code = body['code'];
      if (code is! num || code.toInt() != 0) {
        if (accountChanged) _clearRole();
        return false;
      }
      roleNotifier.value = _roleOf(body);
      _roleAccount = account;
      return true;
    } catch (_) {
      if (accountChanged) _clearRole();
      return false;
    }
  }

  static void _clearRole() {
    roleNotifier.value = '';
    _roleAccount = '';
  }

  /// 从 `/api/login` 响应体取 `data.user.role`；缺失 / 非法值回落 `user`。
  static String _roleOf(Map<String, dynamic> body) {
    final dynamic data = body['data'];
    if (data is! Map) return 'user';
    final dynamic user = data['user'];
    if (user is! Map) return 'user';
    final String value = '${user['role'] ?? ''}'.trim();
    return value == 'admin' || value == 'parent' ? value : 'user';
  }

  static Map<String, dynamic>? _asMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return null;
  }
}
