import 'dart:convert';

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
  ///
  /// `path` 只能传纯路径；查询参数必须通过 [queryParameters] 传入，由
  /// `Uri` 负责编码。若把 `?limit=200` 拼进 `path`，`Uri.replace` 会把
  /// `?` 转义成 `%3F`，服务端收到 `/api/admin/parental/records%3Flimit=200`
  /// 后无法命中路由，落到 SPA 兜底返回 HTML。
  static Uri _uri(String path, {Map<String, dynamic>? queryParameters}) {
    final Uri login = Uri.parse(AppConstants.ptoolsLoginUrl);
    const String loginPath = '/api/login';
    final String fullPath = login.path;
    final String root = fullPath.endsWith(loginPath)
        ? fullPath.substring(0, fullPath.length - loginPath.length)
        : '';
    return login.replace(
      path: '$root$path',
      queryParameters: queryParameters,
    );
  }

  /// 用当前生效凭据换管理会话；失败抛 [ServerApiException]。
  Future<void> ensureAdminSession({
    required String username,
    required String passwordMd5,
  }) async {
    final dynamic data = await DioManager().send(
      url: _uri('/api/admin/login').toString(),
      method: HttpMethod.POST,
      params: <String, dynamic>{'username': username, 'password': passwordMd5},
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
    return _machinesOf(body['machines']);
  }

  /// 当前账号尚未绑定、可自助认领的电视（overview 的 `availableMachines`）。
  ///
  /// 解绑后设备不会从 `machines.json` 删除，而是回到这个列表，家长下次
  /// 进入仍能看到并重新绑定。
  Future<List<ParentalMachine>> fetchAvailableMachines() async {
    final dynamic data = await DioManager().send(
      url: _uri('/api/admin/overview').toString(),
      method: HttpMethod.GET,
      notTipNetError: true,
    );
    final Map<String, dynamic> body = _dataOf(data);
    return _machinesOf(body['availableMachines']);
  }

  static List<ParentalMachine> _machinesOf(dynamic raw) {
    if (raw is! List) return const <ParentalMachine>[];
    return raw
        .whereType<Map>()
        .map(
          (Map item) =>
              ParentalMachine.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList(growable: false);
  }

  /// 家长可见的会话级观看记录（服务端由 parental_watch 心跳还原）。
  Future<List<ParentalSession>> fetchParentalSessions() async {
    final dynamic data = await DioManager().send(
      url: _uri(
        '/api/admin/parental/records',
        queryParameters: <String, dynamic>{'limit': '200'},
      ).toString(),
      method: HttpMethod.GET,
      notTipNetError: true,
    );
    final Map<String, dynamic> body = _dataOf(data);
    final dynamic sessions = body['sessions'];
    if (sessions is! List) return const <ParentalSession>[];
    return sessions
        .whereType<Map>()
        .map(
          (Map item) =>
              ParentalSession.fromJson(Map<String, dynamic>.from(item)),
        )
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
  ///
  /// 返回服务端**落盘后**的配置，调用方据此回读校验（避免请求体未被受理时
  /// 界面仍显示「已保存」）。
  Future<ParentalConfig> saveParental(
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
    final Map<String, dynamic> body = _dataOf(data);
    final dynamic machine = body['machine'];
    if (machine is Map) {
      final dynamic saved = machine['parental'];
      if (saved is Map) {
        return ParentalConfig.fromJson(Map<String, dynamic>.from(saved));
      }
    }
    // 响应缺失时退回请求值（兼容旧服务端），由调用方按需告警。
    return ParentalConfig.fromJson(parental);
  }

  /// 读取某个儿童档案的题库（服务端已归一化，直接回传原始题目 Map）。
  Future<List<Map<String, dynamic>>> fetchQuiz(
    String deviceId,
    String childId,
  ) async {
    final dynamic data = await DioManager().send(
      url: _uri(
        '/api/admin/parental/quiz',
        queryParameters: <String, dynamic>{
          'deviceId': deviceId,
          'childId': childId,
        },
      ).toString(),
      method: HttpMethod.GET,
      notTipNetError: true,
    );
    final Map<String, dynamic> body = _dataOf(data);
    final dynamic raw = body['questions'];
    if (raw is! List) return <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((Map item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  /// 整库替换保存（空列表 = 清空该档案题库）。
  Future<void> saveQuiz(
    String deviceId,
    String childId,
    List<Map<String, dynamic>> questions,
  ) async {
    final dynamic data = await DioManager().send(
      url: _uri('/api/admin/parental/quiz').toString(),
      method: HttpMethod.PUT,
      params: <String, dynamic>{
        'deviceId': deviceId,
        'childId': childId,
        'questions': questions,
      },
      contentType: 'application/json',
      notTipNetError: true,
    );
    _dataOf(data);
  }

  /// 上传题干 / 选项配图，返回服务端相对 URL（题目里只存这个地址）。
  Future<String> uploadQuizImage(
    String deviceId,
    String childId, {
    required List<int> bytes,
    required String mime,
  }) async {
    final dynamic data = await DioManager().send(
      url: _uri('/api/admin/parental/quiz/image').toString(),
      method: HttpMethod.POST,
      params: <String, dynamic>{
        'deviceId': deviceId,
        'childId': childId,
        'mime': mime,
        'data': base64Encode(bytes),
      },
      contentType: 'application/json',
      notTipNetError: true,
    );
    final Map<String, dynamic> body = _dataOf(data);
    return '${body['url'] ?? ''}';
  }

  /// 设置当前账号给这台设备起的私有别名（空串 = 清除，回落默认名称）。
  ///
  /// 服务端返回落盘后的别名；调用方据此更新本地列表，失败时保持旧值并提示。
  Future<String> saveAlias(String deviceId, String alias) async {
    final dynamic data = await DioManager().send(
      url: _uri('/api/admin/machines/$deviceId/alias').toString(),
      method: HttpMethod.PUT,
      params: <String, dynamic>{'alias': alias},
      contentType: 'application/json',
      notTipNetError: true,
    );
    final Map<String, dynamic> body = _dataOf(data);
    return '${body['alias'] ?? ''}';
  }

  /// 家长自助绑定 / 解绑一台电视。
  ///
  /// 走 `POST /api/admin/parental/bind`：`bind:false` 只从 `parents` 数组
  /// 移除当前账号，**不会删除设备记录**；重新绑定用 `bind:true` 即可恢复。
  Future<void> bindDevice(String deviceId, {bool bind = true}) async {
    final dynamic data = await DioManager().send(
      url: _uri('/api/admin/parental/bind').toString(),
      method: HttpMethod.POST,
      params: <String, dynamic>{'deviceId': deviceId, 'bind': bind},
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

/// 一次会话级观看记录。
class ParentalSession {
  const ParentalSession({
    required this.machineId,
    required this.machineName,
    required this.childId,
    required this.childName,
    required this.date,
    required this.startMs,
    required this.endMs,
    required this.durationSec,
    required this.dailySec,
  });

  final String machineId;
  final String machineName;
  final String childId;
  final String childName;
  final String date;
  final int startMs;
  final int endMs;
  final int durationSec;
  final int dailySec;

  factory ParentalSession.fromJson(Map<String, dynamic> json) =>
      ParentalSession(
        machineId: '${json['machineId'] ?? ''}',
        machineName: '${json['machineName'] ?? ''}',
        childId: '${json['childId'] ?? ''}',
        childName: '${json['childName'] ?? ''}',
        date: '${json['date'] ?? ''}',
        startMs: (json['startMs'] as num?)?.toInt() ?? 0,
        endMs: (json['endMs'] as num?)?.toInt() ?? 0,
        durationSec: (json['durationSec'] as num?)?.toInt() ?? 0,
        dailySec: (json['dailySec'] as num?)?.toInt() ?? 0,
      );
}

/// 设备清单中的一台机器（Admin overview 的 machines 条目裁剪）。
class ParentalMachine {
  const ParentalMachine({
    required this.id,
    required this.name,
    this.nameSet = false,
    required this.kind,
    required this.owner,
    required this.parents,
    required this.commAccount,
    this.commDisplayName = '',
    this.alias = '',
    required this.online,
  });

  /// 设备记录主键（`GET /api/device/config` 与 `PUT /api/admin/machines/:id`
  /// 使用的 deviceId）。
  final String id;

  /// 设备备注名（服务端 `machines.json.name`；未设置时服务端填「未命名设备」）。
  final String name;

  /// [name] 是否为管理员真正设置过的备注；false 表示只有「未命名设备」占位。
  final bool nameSet;

  /// 设备类型：`tv`（电视）/ `home`（中控）/ 空字符串（尚未上报）。
  /// 家长控制只处理电视，中控不参与儿童模式与家长绑定。
  final String kind;

  /// 设备所属中控账号（与家长绑定无关）。
  final String owner;

  /// 绑定到该设备的家长账号（可多个）。
  final List<String> parents;

  /// 当前生效的实时通信账号（遥控面板与解锁命令的投递目标）。
  final String commAccount;

  /// 通信账号的展示名（服务端 `_info.txt.displayName`）；空串回落 [commAccount]。
  final String commDisplayName;

  /// 当前登录家长给这台设备起的私有别名（服务端只回传操作者自己那份）；
  /// 空串表示未设置，且不会影响其他家长与 admin 的设备备注。
  final String alias;

  final bool online;

  /// 别名变更后原地更新当前列表项，避免整表重拉导致下拉选中丢焦点。
  ParentalMachine copyWith({String? alias}) => ParentalMachine(
    id: id,
    name: name,
    nameSet: nameSet,
    kind: kind,
    owner: owner,
    parents: parents,
    commAccount: commAccount,
    commDisplayName: commDisplayName,
    alias: alias ?? this.alias,
    online: online,
  );

  factory ParentalMachine.fromJson(Map<String, dynamic> json) =>
      ParentalMachine(
        id: '${json['id'] ?? ''}',
        name: '${json['name'] ?? ''}',
        nameSet: json['nameSet'] == true,
        kind: '${json['kind'] ?? ''}',
        owner: '${json['owner'] ?? ''}',
        parents: (json['parents'] is List)
            ? (json['parents'] as List)
                  .map((dynamic item) => '${item ?? ''}')
                  .where((String item) => item.isNotEmpty)
                  .toList(growable: false)
            : const <String>[],
        commAccount: '${json['commAccount'] ?? ''}',
        commDisplayName: '${json['commDisplayName'] ?? ''}',
        alias: '${json['alias'] ?? ''}',
        online: json['online'] == true,
      );
}
