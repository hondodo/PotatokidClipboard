import 'package:pscreen_home/core/server/server_api.dart';
import 'package:pscreen_home/features/parental/domain/parental_config.dart';
import 'package:pscreen_screen/app/config/app_constants.dart';
import 'package:pscreen_screen/core/network/dio_manager.dart';
import 'package:pscreen_screen/core/network/http_method.dart';

/// 家长视图读写一台 TV 儿童模式配置所用的管理端接口（与 Admin 页同一
/// Node 服务，Cookie 由 Dio 的持久化 cookie jar 自动携带）：
///
/// - `POST /api/admin/login` 换管理会话（`pk_admin` cookie）——服务端把
///   「家长操作」放行给 `parent` + `admin` 后家长端即可写入（服务端枚举
///   扩展由服务端任务负责，落地前 parent 会在此收到「不是管理员」失败）；
/// - `GET  /api/admin/overview` 拉设备清单（id / owner / commAccount / 在线）；
/// - `GET  /api/device/config?deviceId=` 读生效配置里的 `parental` 字段；
/// - `PUT  /api/admin/machines/:id` 携带 `parental` 字段写入（方案 4.3
///   指定落点；服务端 parental 存储落地前该字段可能不持久）。
class ParentalAdminApi {
  const ParentalAdminApi();

  /// `/api/admin/*` 与 `/api/login` 同源：取登录地址的路径根拼接。
  static Uri _uri(String path) {
    final Uri login = Uri.parse(AppConstants.ptoolsLoginUrl);
    const String loginPath = '/api/login';
    final String fullPath = login.path;
    final String root = fullPath.endsWith(loginPath)
        ? fullPath.substring(0, fullPath.length - loginPath.length)
        : '';
    return login.replace(path: '$root$path', queryParameters: null);
  }

  /// 用当前生效凭据换管理会话；失败抛 [ServerApiException]。
  Future<void> ensureAdminSession({
    required String username,
    required String passwordMd5,
  }) async {
    final dynamic data = await DioManager().send(
      url: _uri('/api/admin/login').toString(),
      method: HttpMethod.POST,
      params: <String, dynamic>{
        'username': username,
        'password': passwordMd5,
      },
      contentType: 'application/json',
      notTipNetError: true,
    );
    _dataOf(data);
  }

  /// 设备清单（overview 的 machines 条目裁剪）。
  Future<List<ParentalMachine>> fetchMachines() async {
    final dynamic data = await DioManager().send(
      url: _uri('/api/admin/overview').toString(),
      method: HttpMethod.GET,
      notTipNetError: true,
    );
    final Map<String, dynamic> body = _dataOf(data);
    final dynamic machines = body['machines'];
    if (machines is! List) return const <ParentalMachine>[];
    return machines
        .whereType<Map>()
        .map((Map item) =>
            ParentalMachine.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false);
  }

  /// 读一台设备当前生效的 `parental` 配置；服务端未落地该字段时返回空配置。
  Future<ParentalConfig> fetchParental(String deviceId) async {
    final dynamic data = await DioManager().send(
      url: _uri('/api/device/config').toString(),
      method: HttpMethod.GET,
      params: <String, dynamic>{'deviceId': deviceId},
      notTipNetError: true,
    );
    final Map<String, dynamic> body = _dataOf(data);
    final dynamic config = body['config'];
    if (config is! Map) return ParentalConfig.empty;
    final dynamic parental = config['parental'];
    if (parental is! Map) return ParentalConfig.empty;
    return ParentalConfig.fromJson(Map<String, dynamic>.from(parental));
  }

  /// 携带 `parental` 字段写入设备记录（方案 4.3 指定的档案 CRUD 落点）。
  Future<void> saveParental(
    String deviceId,
    Map<String, dynamic> parental,
  ) async {
    final dynamic data = await DioManager().send(
      url: _uri('/api/admin/machines/$deviceId').toString(),
      method: HttpMethod.PUT,
      params: <String, dynamic>{'parental': parental},
      contentType: 'application/json',
      notTipNetError: true,
    );
    _dataOf(data);
  }

  /// 校验业务 `code`；非 0 抛 [ServerApiException]（带服务端 msg），
  /// 否则返回响应的 `data` 节。
  static Map<String, dynamic> _dataOf(dynamic data) {
    if (data is! Map) throw const ServerApiException('服务端返回格式错误');
    final Map<String, dynamic> body = data is Map<String, dynamic>
        ? data
        : Map<String, dynamic>.from(data);
    final int code = (body['code'] as num?)?.toInt() ?? -1;
    if (code != 0) {
      throw ServerApiException('${body['msg'] ?? '请求失败'}', code: code);
    }
    final dynamic inner = body['data'];
    if (inner is Map<String, dynamic>) return inner;
    if (inner is Map) return Map<String, dynamic>.from(inner);
    return <String, dynamic>{};
  }
}

/// 设备清单中的一台机器（Admin overview 的 machines 条目裁剪）。
class ParentalMachine {
  const ParentalMachine({
    required this.id,
    required this.name,
    required this.owner,
    required this.commAccount,
    required this.online,
  });

  /// 设备记录主键（`GET /api/device/config` 与 `PUT /api/admin/machines/:id`
  /// 使用的 deviceId）。
  final String id;

  /// 设备显示名。
  final String name;

  /// 归属账号（`parent` 角色只看 `owner == 本账号`，admin 放开代管）。
  final String owner;

  /// 当前生效的实时通信账号（遥控面板与解锁命令的投递目标）。
  final String commAccount;

  final bool online;

  factory ParentalMachine.fromJson(Map<String, dynamic> json) =>
      ParentalMachine(
        id: '${json['id'] ?? ''}',
        name: '${json['name'] ?? ''}',
        owner: '${json['owner'] ?? ''}',
        commAccount: '${json['commAccount'] ?? ''}',
        online: json['online'] == true,
      );
}
