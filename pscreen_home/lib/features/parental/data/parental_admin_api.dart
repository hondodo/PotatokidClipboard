import 'dart:convert';

import 'package:pscreen_home/core/server/server_api.dart';
import 'package:pscreen_home/features/parental/domain/parental_config.dart';
import 'package:pscreen_home/features/parental/domain/parental_share.dart';
import 'package:pscreen_screen/app/config/app_constants.dart';
import 'package:pscreen_screen/core/network/dio_manager.dart';
import 'package:pscreen_screen/core/network/http_method.dart';
import 'package:pscreen_screen/core/network/net_exceptions.dart';

/// 设置家长号成功后服务端返回的账号。
///
/// 口令由用户在此前自设（不再由服务端随机下发只存本机），因此响应只回账号名；
/// 客户端把「家长号 + 自设口令」一起持久化，换设备凭这两项即可登录。
/// 实时通道仍恒用设备派生号，与这里无关。
class ClaimAccountResult {
  const ClaimAccountResult({required this.account, required this.password});

  final String account;

  /// 用户自设口令，原样回传便于调用方统一持久化（与旧接口签名兼容）。
  final String password;
}

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
/// D-01：并发写入冲突（服务端返回 HTTP 409 + 当前实体版本/内容）。
///
/// 调用方捕获后应提示用户并回读最新值，避免静默覆盖他人修改。
class ParentalConflictException implements Exception {
  const ParentalConflictException(this.message, {this.current});

  final String message;

  /// 服务端当前的实体快照（含 `revision` 与业务字段），供展示差异 / 覆盖使用。
  final Map<String, dynamic>? current;

  @override
  String toString() => message;
}

/// 把 409 冲突响应转成 [ParentalConflictException]，其余错误原样抛出。
Future<dynamic> _guardConflict(Future<dynamic> Function() action) async {
  try {
    return await action();
  } on HttpCodeException catch (e) {
    final dynamic body = e.body;
    if (e.httpCode == 409 && body is Map) {
      final Map<String, dynamic> map = Map<String, dynamic>.from(body);
      final dynamic data = map['data'];
      final Map<String, dynamic>? current = data is Map && data['current'] is Map
          ? Map<String, dynamic>.from(data['current'] as Map)
          : null;
      throw ParentalConflictException(
        '${map['msg'] ?? '数据已被其他设备修改，请刷新后再试'}',
        current: current,
      );
    }
    rethrow;
  }
}

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

  /// 读取某台电视的档案共享视图（主本 / 已引用含 broken / 可引用候选）。
  ///
  /// overview 已随每台机器下发 `parentalShareView`，进入共享页时优先用缓存；
  /// 写操作后服务端会把最新 view 一并返回，这里统一解析，避免再拉一次 overview。
  Future<ParentalShareView> fetchShareView(String deviceId) async {
    final dynamic data = await DioManager().send(
      url: _uri(
        '/api/admin/parental/shared-view',
        queryParameters: <String, dynamic>{'deviceId': deviceId},
      ).toString(),
      method: HttpMethod.GET,
      notTipNetError: true,
    );
    return _shareViewOf(_dataOf(data));
  }

  /// 设置本台某个主本档案的「对外分享」家长号白名单。
  ///
  /// 只有 `children[]` 里的主本能改；`shared[]` 引用档案无权设置。
  /// 留空列表＝取消分享，任何其他家长都看不到这份档案。
  Future<ParentalShareView> setChildSharedTo(
    String deviceId,
    String childId,
    List<String> sharedTo,
  ) async {
    final dynamic data = await DioManager().send(
      url: _uri('/api/admin/parental/share-to').toString(),
      method: HttpMethod.PUT,
      params: <String, dynamic>{
        'deviceId': deviceId,
        'childId': childId,
        'sharedTo': sharedTo,
      },
      contentType: 'application/json',
      notTipNetError: true,
    );
    return _shareViewOf(_dataOf(data));
  }

  /// 在当前电视上引用一个可见的主本档案（只存坐标，不复制内容）。
  Future<ParentalShareView> addSharedRef(
    String deviceId, {
    required String fromMachineId,
    required String fromChildId,
  }) async {
    final dynamic data = await DioManager().send(
      url: _uri('/api/admin/parental/shared').toString(),
      method: HttpMethod.POST,
      params: <String, dynamic>{
        'deviceId': deviceId,
        'fromMachineId': fromMachineId,
        'fromChildId': fromChildId,
      },
      contentType: 'application/json',
      notTipNetError: true,
    );
    return _shareViewOf(_dataOf(data));
  }

  /// 取消一条引用：只删本台 `shared[]` 坐标，绝不触碰主本档案。
  Future<ParentalShareView> cancelSharedRef(
    String deviceId,
    String refId,
  ) async {
    final dynamic data = await DioManager().send(
      url: _uri('/api/admin/parental/shared').toString(),
      method: HttpMethod.DELETE,
      params: <String, dynamic>{'deviceId': deviceId, 'refId': refId},
      contentType: 'application/json',
      notTipNetError: true,
    );
    return _shareViewOf(_dataOf(data));
  }

  static ParentalShareView _shareViewOf(Map<String, dynamic> body) {
    final dynamic view = body['view'];
    if (view is Map) {
      return ParentalShareView.fromJson(Map<String, dynamic>.from(view));
    }
    // 兼容 overview 直接嵌 `parentalShareView` 的响应形态。
    final dynamic embedded = body['parentalShareView'];
    if (embedded is Map) {
      return ParentalShareView.fromJson(Map<String, dynamic>.from(embedded));
    }
    return ParentalShareView.empty;
  }

  /// 读取某个儿童档案的题库（服务端已归一化，直接回传原始题目 Map）。
  Future<List<Map<String, dynamic>>> fetchQuiz(
    String deviceId,
    String childId,
  ) async {
    final ParentalQuizState state = await fetchQuizState(deviceId, childId);
    return state.questions;
  }

  /// 读取题库 + 当前版本号（D-01：保存时作为 `baseRevision` 回传）。
  Future<ParentalQuizState> fetchQuizState(
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
    return ParentalQuizState(
      questions: raw is! List
          ? const <Map<String, dynamic>>[]
          : raw
              .whereType<Map>()
              .map((Map item) => Map<String, dynamic>.from(item))
              .toList(growable: false),
      revision: (body['revision'] as num?)?.toInt() ?? 0,
    );
  }

  /// 整库替换保存（空列表 = 清空该档案题库）。
  ///
  /// D-01：携带 `baseRevision` 时服务端做版本守卫，冲突抛 [ParentalConflictException]。
  Future<void> saveQuiz(
    String deviceId,
    String childId,
    List<Map<String, dynamic>> questions, {
    int? baseRevision,
  }) async {
    final dynamic data = await _guardConflict(() => DioManager().send(
          url: _uri('/api/admin/parental/quiz').toString(),
          method: HttpMethod.PUT,
          params: <String, dynamic>{
            'deviceId': deviceId,
            'childId': childId,
            'questions': questions,
            'baseRevision': ?baseRevision,
          },
          contentType: 'application/json',
          notTipNetError: true,
        ));
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

  /// 上传儿童档案头像：base64 → 返回 app_server 公网直链。
  /// 服务端自动按 sha256 去重（同一张图第二次上传会复用已有 URL）。
  ///
  /// [onSendProgress] 可选：客户端压成 512×512 PNG 后约 150–300KB，
  /// JSON + base64 后 HTTP body ~400KB；在局域网里 ~100ms 就能发完，
  /// 但给个回调让上层决定要不要显示进度（比如编辑器里的上涨条）。
  Future<String> uploadAvatar(
    String deviceId, {
    required List<int> bytes,
    void Function(int sent, int total)? onSendProgress,
  }) async {
    final dynamic data = await DioManager().send(
      url: _uri('/api/admin/parental/avatar').toString(),
      method: HttpMethod.POST,
      params: <String, dynamic>{
        'deviceId': deviceId,
        'data': base64Encode(bytes),
      },
      contentType: 'application/json',
      notTipNetError: true,
      onSendProgress: onSendProgress,
    );
    final Map<String, dynamic> body = _dataOf(data);
    final String url = '${body['url'] ?? ''}';
    if (url.isEmpty) {
      throw const ServerApiException('头像上传失败：未返回地址');
    }
    return url;
  }

  // -------------------------------------------------- 家庭级主档案（D-02 / Task 32）

  /// 列出全部家庭儿童主档案（全局），并附每台电视的分配情况与题库分享白名单。
  ///
  /// 全局唯一、不含 deviceId；规则（限额 / 禁看时段 / 黑白名单 / 档位）全部归这里。
  Future<List<FamilyChild>> fetchFamilyChildren() async {
    final dynamic data = await DioManager().send(
      url: _uri('/api/admin/parental/children').toString(),
      method: HttpMethod.GET,
      notTipNetError: true,
    );
    final Map<String, dynamic> body = _dataOf(data);
    final dynamic raw = body['children'];
    if (raw is! List) return const <FamilyChild>[];
    return raw
        .whereType<Map>()
        .map((Map item) => FamilyChild.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false);
  }

  /// 新增 / 更新一个全局儿童主档案（按 childId 全局唯一，覆盖写）。
  ///
  /// [child] 须包含 `id` / `name`；服务端按 childId upsert 并推送已分配电视。
  Future<FamilyChild> saveFamilyChild(Map<String, dynamic> child, {int? baseRevision}) async {
    final dynamic data = await _guardConflict(() => DioManager().send(
          url: _uri('/api/admin/parental/child').toString(),
          method: HttpMethod.POST,
          params: <String, dynamic>{
            ...child,
            'baseRevision': ?baseRevision,
          },
          contentType: 'application/json',
          notTipNetError: true,
        ));
    final Map<String, dynamic> body = _dataOf(data);
    final dynamic saved = body['child'];
    if (saved is Map) {
      return FamilyChild.fromJson(Map<String, dynamic>.from(saved));
    }
    // 响应缺失时退回请求值（兼容旧服务端），由调用方按需告警。
    return FamilyChild.fromJson(child);
  }

  /// 删除一个全局儿童主档案（级联清空各电视分配），需二次确认后调用。
  Future<void> deleteFamilyChild(String childId) async {
    final dynamic data = await DioManager().send(
      url: _uri('/api/admin/parental/child').toString(),
      method: HttpMethod.DELETE,
      params: <String, dynamic>{'childId': childId},
      contentType: 'application/json',
      notTipNetError: true,
    );
    _dataOf(data);
  }

  /// 读取某台电视当前启用的家庭档案分配（childIds 列表）。
  Future<List<String>> fetchAssignment(String deviceId) async {
    final dynamic data = await DioManager().send(
      url: _uri(
        '/api/admin/parental/assignment',
        queryParameters: <String, dynamic>{'deviceId': deviceId},
      ).toString(),
      method: HttpMethod.GET,
      notTipNetError: true,
    );
    final Map<String, dynamic> body = _dataOf(data);
    return _stringList(body['childIds']);
  }

  /// 设置某台电视启用的家庭档案分配（勾选哪些档案在本台生效）。
  Future<List<String>> saveAssignment(
    String deviceId,
    List<String> childIds, {
    int? baseRevision,
  }) async {
    final dynamic data = await _guardConflict(() => DioManager().send(
          url: _uri('/api/admin/parental/assignment').toString(),
          method: HttpMethod.PUT,
          params: <String, dynamic>{
            'deviceId': deviceId,
            'childIds': childIds,
            'baseRevision': ?baseRevision,
          },
          contentType: 'application/json',
          notTipNetError: true,
        ));
    final Map<String, dynamic> body = _dataOf(data);
    return _stringList(body['childIds']);
  }

  /// 读取某台电视的分配 + 当前版本号（D-01：保存时回传 baseRevision）。
  Future<ParentalAssignment> fetchAssignmentState(String deviceId) async {
    final dynamic data = await DioManager().send(
      url: _uri(
        '/api/admin/parental/assignment',
        queryParameters: <String, dynamic>{'deviceId': deviceId},
      ).toString(),
      method: HttpMethod.GET,
      notTipNetError: true,
    );
    final Map<String, dynamic> body = _dataOf(data);
    return ParentalAssignment(
      deviceId: deviceId,
      childIds: _stringList(body['childIds']),
      revision: (body['revision'] as num?)?.toInt() ?? 0,
    );
  }

  /// 读取某台电视的本台设置（CR-02：解锁方式 / PIN / 儿童模式开关 / 已应用档案）。
  Future<ParentalDeviceLocal> fetchDeviceLocal(String deviceId) async {
    final dynamic data = await DioManager().send(
      url: _uri(
        '/api/admin/parental/device-local',
        queryParameters: <String, dynamic>{'deviceId': deviceId},
      ).toString(),
      method: HttpMethod.GET,
      notTipNetError: true,
    );
    return ParentalDeviceLocal.fromJson(_dataOf(data));
  }

  /// 写入某台电视的本台设置（CR-02 + D-01：带 baseRevision 时冲突返回 409）。
  Future<ParentalDeviceLocal> saveDeviceLocal(
    String deviceId, {
    String? mode,
    String? unlockMode,
    String? pin,
    List<String>? activeChildIds,
    int? baseRevision,
  }) async {
    final dynamic data = await _guardConflict(() => DioManager().send(
          url: _uri('/api/admin/parental/device-local').toString(),
          method: HttpMethod.PUT,
          params: <String, dynamic>{
            'deviceId': deviceId,
            'mode': ?mode,
            'unlockMode': ?unlockMode,
            'pin': ?pin,
            'activeChildIds': ?activeChildIds,
            'baseRevision': ?baseRevision,
          },
          contentType: 'application/json',
          notTipNetError: true,
        ));
    return ParentalDeviceLocal.fromJson(_dataOf(data));
  }

  // -------------------------------------------------- 题库分享（CR-01）

  /// CR-01：设置某儿童题库的跨家长分享白名单（只授权账号，不传 childId）。
  ///
  /// 返回服务端落盘后的白名单；调用方据此更新本地列表，失败时保持旧值并提示。
  Future<List<String>> setQuizShare(String childId, List<String> sharedTo, {int? baseRevision}) async {
    final dynamic data = await _guardConflict(() => DioManager().send(
          url: _uri('/api/admin/parental/quiz/share').toString(),
          method: HttpMethod.PUT,
          params: <String, dynamic>{
            'childId': childId,
            'sharedTo': sharedTo,
            'baseRevision': ?baseRevision,
          },
          contentType: 'application/json',
          notTipNetError: true,
        ));
    final Map<String, dynamic> body = _dataOf(data);
    final dynamic st = body['sharedTo'];
    if (st is List) {
      return st
          .map((dynamic e) => '$e')
          .where((String e) => e.isNotEmpty)
          .toList(growable: false);
    }
    return sharedTo;
  }

  /// CR-01 Q1：从他人分享的题库复制一份到自己的儿童档案（不引用、不共账）。
  Future<Map<String, dynamic>> importQuizCopy({
    required String targetChildId,
    required String sourceChildId,
    required String sourceAccount,
  }) async {
    final dynamic data = await DioManager().send(
      url: _uri('/api/admin/parental/quiz/import').toString(),
      method: HttpMethod.POST,
      params: <String, dynamic>{
        'targetChildId': targetChildId,
        'sourceChildId': sourceChildId,
        'sourceAccount': sourceAccount,
      },
      contentType: 'application/json',
      notTipNetError: true,
    );
    return _dataOf(data);
  }

  /// CR-01：列出分享给我的题库（他人 `sharedTo` 含我），用于一键复制副本。
  ///
  /// 仅含匿名聚合信息（来源账号 / 来源 childId / 题目数），不含使用统计（Q3）。
  Future<List<SharedQuizInfo>> fetchSharedToMeQuizzes() async {
    final dynamic data = await DioManager().send(
      url: _uri('/api/admin/parental/quiz/shared-to-me').toString(),
      method: HttpMethod.GET,
      notTipNetError: true,
    );
    final Map<String, dynamic> body = _dataOf(data);
    final dynamic raw = body['quizzes'];
    if (raw is! List) return const <SharedQuizInfo>[];
    return raw
        .whereType<Map>()
        .map((Map item) => SharedQuizInfo.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false);
  }

  /// 列出当前家长可用的头像素材（所有能管理的 TV 的头像合并、按 sha256 去重）。
  Future<List<AvatarItem>> listAvatars() async {
    final dynamic data = await DioManager().send(
      url: _uri('/api/admin/parental/avatars').toString(),
      method: HttpMethod.GET,
      notTipNetError: true,
    );
    final Map<String, dynamic> body = _dataOf(data);
    final dynamic raw = body['avatars'];
    if (raw is! List) return const <AvatarItem>[];
    return raw
        .whereType<Map>()
        .map(
          (Map item) => AvatarItem.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList(growable: false);
  }

  /// 从家长可用的头像列表移除某个素材（不会删除 app_server 上的物理文件，
  /// 因为其他电视/档案可能还在引用同一个 sha256 的图）。
  Future<void> deleteAvatar(String avatarId) async {
    await DioManager().send(
      url: _uri('/api/admin/parental/avatar/$avatarId').toString(),
      method: HttpMethod.DELETE,
      notTipNetError: true,
    );
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

  /// 领取「设置家长号」的一次性凭证（服务端签发，短时有效）。
  ///
  /// 需先用设备派生号调 [ensureAdminSession] 拿到 `pk_admin` 会话；服务端只给
  /// 设备自举的 parent 账号签票，且一台设备只能关联一次家长号。
  Future<String> requestClaimTicket() async {
    final dynamic data = await DioManager().send(
      url: _uri('/api/admin/claim/ticket').toString(),
      method: HttpMethod.POST,
      params: <String, dynamic>{},
      contentType: 'application/json',
      notTipNetError: true,
    );
    final Map<String, dynamic> body = _dataOf(data);
    final String token = '${body['claimToken'] ?? ''}'.trim();
    if (token.isEmpty) throw const ServerApiException('服务端未返回凭证');
    return token;
  }

  /// 建立家长号与本机派生号的关联（两层身份并存，派生号永不改名/禁用）。
  ///
  /// 服务端只新建家长号账号（口令为用户自设）并把 `parents` / 私有别名 /
  /// 儿童模式归属从派生号映射到家长号；设备 commAccount、题库、事件历史不动。
  /// 成功后客户端把「家长号 + 自设口令」一起持久化，此后 HTTP 管理登录用家长号，
  /// 实时通道仍恒用派生号 + principal 握手，互不影响。
  Future<ClaimAccountResult> claimAccount({
    required String account,
    required String password,
    required String claimToken,
  }) async {
    final dynamic data = await DioManager().send(
      url: _uri('/api/admin/claim').toString(),
      method: HttpMethod.POST,
      params: <String, dynamic>{
        'account': account.trim(),
        'password': password,
        'claimToken': claimToken,
      },
      contentType: 'application/json',
      notTipNetError: true,
    );
    final Map<String, dynamic> body = _dataOf(data);
    final String name = '${body['account'] ?? ''}'.trim();
    if (name.isEmpty) throw const ServerApiException('服务端未返回家长号');
    // 口令是用户自设的，服务端不再回传；用请求值回填结果，统一持久化入口。
    return ClaimAccountResult(account: name, password: password);
  }

  /// 已用家长号登录后修改口令。派生号账号口令恒为 123456，不受影响。
  Future<void> changeParentPassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final dynamic data = await DioManager().send(
      url: _uri('/api/admin/parent-account/password').toString(),
      method: HttpMethod.POST,
      params: <String, dynamic>{
        'currentPassword': currentPassword,
        'newPassword': newPassword,
      },
      contentType: 'application/json',
      notTipNetError: true,
    );
    _dataOf(data);
  }

  /// 用「家长号 + 口令」校验能否登录（跨设备登录用）。
  ///
  /// 直接打 `/api/login`：账号存在且口令 MD5 一致即成功，返回 `data.user.role`。
  /// 与实时通道无关——ws 侧另用派生号 + principal 握手。
  Future<String> loginRole({
    required String account,
    required String passwordMd5,
  }) async {
    final dynamic data = await DioManager().send(
      url: _uri('/api/login').toString(),
      method: HttpMethod.POST,
      params: <String, dynamic>{'username': account.trim(), 'password': passwordMd5},
      contentType: 'application/json',
      notTipNetError: true,
    );
    final Map<String, dynamic> body = _dataOf(data);
    final dynamic user = body['user'];
    if (user is Map) return '${user['role'] ?? ''}'.trim();
    return '';
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
    this.shareView,
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

  /// overview 预展开的档案共享视图；只有 tv 机器会有，非 tv 为 null。
  /// 写接口返回新 view 后由页面壳原地替换，避免整页重拉。
  final ParentalShareView? shareView;

  /// 别名变更后原地更新当前列表项，避免整表重拉导致下拉选中丢焦点。
  ParentalMachine copyWith({String? alias, ParentalShareView? shareView}) =>
      ParentalMachine(
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
        shareView: shareView ?? this.shareView,
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
        shareView: json['parentalShareView'] is Map
            ? ParentalShareView.fromJson(
                Map<String, dynamic>.from(json['parentalShareView'] as Map),
              )
            : null,
      );
}

/// 一张上传到 app_server 并已镜像到公网的儿童档案头像素材。
class AvatarItem {
  const AvatarItem({
    required this.id,
    required this.url,
    required this.sha256,
    this.mime = 'image/png',
    this.size = 0,
    this.uploadedBy = '',
    this.createdAt = '',
  });

  final String id;
  final String url;
  final String sha256;
  final String mime;
  final int size;
  final String uploadedBy;
  final String createdAt;

  factory AvatarItem.fromJson(Map<String, dynamic> json) => AvatarItem(
        id: '${json['id'] ?? ''}',
        url: '${json['url'] ?? ''}',
        sha256: '${json['sha256'] ?? ''}',
        mime: '${json['mime'] ?? 'image/png'}',
        size: (json['size'] as num?)?.toInt() ?? 0,
        uploadedBy: '${json['uploadedBy'] ?? ''}',
        createdAt: '${json['createdAt'] ?? ''}',
      );
}

/// D-01：某个儿童题库的读取结果（题目 + 版本号）。
class ParentalQuizState {
  const ParentalQuizState({required this.questions, required this.revision});

  final List<Map<String, dynamic>> questions;
  final int revision;
}

/// D-01：某台电视的分配状态（childIds + 版本号）。
class ParentalAssignment {
  const ParentalAssignment({
    required this.deviceId,
    required this.childIds,
    required this.revision,
  });

  final String deviceId;
  final List<String> childIds;
  final int revision;
}

/// CR-02：某台电视的本台设置（儿童模式开关 / 解锁方式 / PIN / 已应用档案）。
class ParentalDeviceLocal {
  const ParentalDeviceLocal({
    required this.deviceId,
    this.mode = 'off',
    this.unlockMode = 'remote',
    this.pin = '',
    this.activeChildIds = const <String>[],
    this.revision = 0,
  });

  final String deviceId;
  final String mode;
  final String unlockMode;
  final String pin;
  final List<String> activeChildIds;
  final int revision;

  bool get enabled => mode == 'on';

  factory ParentalDeviceLocal.fromJson(Map<String, dynamic> json) =>
      ParentalDeviceLocal(
        deviceId: '${json['deviceId'] ?? ''}',
        mode: '${json['mode'] ?? 'off'}' == 'on' ? 'on' : 'off',
        unlockMode: '${json['unlockMode'] ?? 'remote'}',
        pin: '${json['pin'] ?? ''}',
        activeChildIds: _stringList(json['activeChildIds']),
        revision: (json['revision'] as num?)?.toInt() ?? 0,
      );
}

/// 安全解析字符串列表（服务端返回可能为 null / 非数组）。
List<String> _stringList(dynamic value) {
  if (value is! List) return const <String>[];
  return value
      .map((dynamic item) => '${item ?? ''}'.trim())
      .where((String item) => item.isNotEmpty)
      .toList(growable: false);
}
