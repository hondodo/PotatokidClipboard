import 'dart:async';
import 'dart:convert';

import 'package:pscreen_screen/app/app_log.dart';
import 'package:pscreen_screen/app/config/app_constants.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// 实时通道连接状态。
enum RealtimeConnectionState { disconnected, connecting, connected, error }

/// 一条实时消息。
class RealtimeMessage {
  const RealtimeMessage({
    required this.id,
    required this.from,
    required this.to,
    required this.body,
    required this.ts,
  });

  final String id;
  final String from;
  final String to;
  final String body;
  final int ts;

  factory RealtimeMessage.fromJson(Map<String, dynamic> json) => RealtimeMessage(
        id: '${json['id'] ?? ''}',
        from: '${json['from'] ?? ''}',
        to: '${json['to'] ?? ''}',
        body: '${json['body'] ?? ''}',
        ts: (json['ts'] as num?)?.toInt() ?? 0,
      );
}

/// 一条结构化事件（场景变化 / HA 操作等）。
class RealtimeEvent {
  const RealtimeEvent({
    required this.id,
    required this.from,
    required this.to,
    required this.event,
    required this.data,
    required this.ts,
  });

  final String id;
  final String from;
  final String to;
  final String event;
  final Map<String, dynamic> data;
  final int ts;

  factory RealtimeEvent.fromJson(Map<String, dynamic> json) {
    final dynamic rawData = json['data'];
    return RealtimeEvent(
      id: '${json['id'] ?? ''}',
      from: '${json['from'] ?? ''}',
      to: '${json['to'] ?? ''}',
      event: '${json['event'] ?? ''}',
      data: rawData is Map<String, dynamic>
          ? Map<String, dynamic>.unmodifiable(rawData)
          : const <String, dynamic>{},
      ts: (json['ts'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 合并会话线程的一条记录：聊天消息或结构化事件。
///
/// 用于控制端查看「当前账号 + 管理员」与某台设备之间的完整往来：
/// `kind == 'msg'` 时取 [text]，`kind == 'event'` 时取 [event] 与 [data]。
class RealtimeThreadItem {
  const RealtimeThreadItem({
    required this.kind,
    required this.id,
    required this.from,
    required this.to,
    required this.ts,
    this.text = '',
    this.event = '',
    this.data = const <String, Object?>{},
  });

  final String kind;
  final String id;
  final String from;
  final String to;
  final int ts;
  final String text;
  final String event;
  final Map<String, Object?> data;

  bool get isEvent => kind == 'event';

  factory RealtimeThreadItem.fromJson(Map<String, dynamic> json) {
    final dynamic rawData = json['data'];
    return RealtimeThreadItem(
      kind: '${json['kind'] ?? 'msg'}',
      id: '${json['id'] ?? ''}',
      from: '${json['from'] ?? ''}',
      to: '${json['to'] ?? ''}',
      ts: (json['ts'] as num?)?.toInt() ?? 0,
      text: '${json['text'] ?? ''}',
      event: '${json['event'] ?? ''}',
      data: rawData is Map<String, dynamic>
          ? Map<String, Object?>.unmodifiable(rawData)
          : const <String, Object?>{},
    );
  }
}

/// 在线状态变更。
class RealtimePresence {
  const RealtimePresence({required this.account, required this.online});

  final String account;
  final bool online;
}

/// 面板类型推断：旧服务端/旧客户端不回显 `kind` 时按包名兜底。
///
/// 返回值：`home`（中控屏）、`tv`（电视端）、空串（未知）。
String kindOfApp(String app) {
  switch (app) {
    case 'potatokid.tools.homecontroller':
      return 'home';
    case 'screen.potatokid.tools':
    case 'screen.potatokid.potatokid_screen':
    case 'potatokid_screen':
      return 'tv';
    default:
      return '';
  }
}

/// 一台被控设备的已知状态（由 ready.roster / presence / state 帧累积）。
///
/// 控制端据此决定显示哪种遥控面板（[kind]）以及当前场景/频道列表。
class RealtimeDeviceState {
  const RealtimeDeviceState({
    required this.account,
    this.kind = '',
    this.app = '',
    this.version = '',
    this.build = '',
    this.scene = const <String, Object?>{},
    this.channels = const <String>[],
    this.listVersion = '',
    this.playback = const <String, Object?>{},
    this.ts = 0,
  });

  final String account;

  /// 面板类型：`home` / `tv` / 空串。
  final String kind;
  final String app;
  final String version;
  final String build;

  /// 最新场景快照（[SceneSnapshot.toJson] 的结构）。
  final Map<String, Object?> scene;

  /// 完整频道名列表（首次连接/列表变化时才下发）。
  final List<String> channels;

  /// 频道列表版本（FNV-1a 摘要），列表未变时复用。
  final String listVersion;

  /// 当前直播播放状态（`channel`/`state`/`label`/`ts`）；空 map = 未在播放。
  ///
  /// 只有直播场景才会带值，离开直播后服务端会收到 null 并被清空。
  final Map<String, Object?> playback;

  /// 服务端收到该状态的本地时间戳。
  final int ts;

  /// 场景类型名（如 `live` / `home` / `screensaver`）。
  String get sceneKind => '${scene['kind'] ?? ''}';

  /// 当前播放频道名（直播场景才有）。
  String get channelName => '${scene['channelName'] ?? ''}';

  /// 播放状态文案（如「播放正常」）；未直播/未上报时为空串。
  String get playbackLabel => '${playback['label'] ?? ''}';

  /// 播放状态原始名（`play_ok` / `play_retry` / `play_fail` / `play_start`）。
  String get playbackState => '${playback['state'] ?? ''}';

  /// 播放状态所属频道（可能与 [channelName] 短暂不一致）。
  String get playbackChannel => '${playback['channel'] ?? ''}';

  RealtimeDeviceState copyWith({
    String? kind,
    String? app,
    String? version,
    String? build,
    Map<String, Object?>? scene,
    List<String>? channels,
    String? listVersion,
    Map<String, Object?>? playback,
    int? ts,
  }) =>
      RealtimeDeviceState(
        account: account,
        kind: kind ?? this.kind,
        app: app ?? this.app,
        version: version ?? this.version,
        build: build ?? this.build,
        scene: scene ?? this.scene,
        channels: channels ?? this.channels,
        listVersion: listVersion ?? this.listVersion,
        playback: playback ?? this.playback,
        ts: ts ?? this.ts,
      );
}

/// 会话摘要（服务端按历史消息聚合）。
class RealtimeConversation {
  const RealtimeConversation({
    required this.account,
    required this.lastMessage,
    required this.ts,
    required this.unread,
  });

  final String account;
  final String lastMessage;
  final int ts;
  final int unread;
}

/// 实时通道异常（鉴权失败 / 连接失败）。
class RealtimeException implements Exception {
  const RealtimeException(this.code, [this.message]);

  final int code;
  final String? message;

  @override
  String toString() => 'RealtimeException(code: $code, message: $message)';
}

/// 自建 WebSocket 网关的客户端：负责连接、重连、收发、历史与在线状态。
///
/// 协议（JSON）：
/// - 客户端 → 服务端：`msg` / `event` / `events` / `history` / `conversations`
///   / `read` / `ping`
/// - 服务端 → 客户端：`ready` / `msg` / `event` / `events` / `result` / `presence`
///   / `history` / `conversations` / `error` / `pong`
class RealtimeChannel {
  RealtimeChannel({String? url}) : _url = url ?? AppConstants.realtimeWsUrl;

  final String _url;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  Completer<bool>? _readyGate;

  final Map<String, Completer<Map<String, dynamic>>> _pending =
      <String, Completer<Map<String, dynamic>>>{};

  final StreamController<RealtimeConnectionState> _stateController =
      StreamController<RealtimeConnectionState>.broadcast();
  final StreamController<RealtimeMessage> _messageController =
      StreamController<RealtimeMessage>.broadcast();
  final StreamController<RealtimeEvent> _eventController =
      StreamController<RealtimeEvent>.broadcast();
  final StreamController<RealtimePresence> _presenceController =
      StreamController<RealtimePresence>.broadcast();
  final StreamController<String> _errorController =
      StreamController<String>.broadcast();
  final StreamController<void> _conversationController =
      StreamController<void>.broadcast();
  final StreamController<RealtimeDeviceState> _deviceController =
      StreamController<RealtimeDeviceState>.broadcast();

  RealtimeConnectionState _state = RealtimeConnectionState.disconnected;
  final Set<String> _online = <String>{};

  /// account → 已累积的设备状态（roster / presence / state）。
  final Map<String, RealtimeDeviceState> _devices =
      <String, RealtimeDeviceState>{};

  /// 正在订阅状态的账号（重连后自动重发 watch）。
  final Set<String> _watched = <String>{};

  /// 正在订阅的合并会话线程：peer -> 额外参与账号（管理员）（重连后补发）。
  final Map<String, List<String>> _watchedThreads = <String, List<String>>{};

  String _account = '';
  String _token = '';
  String _deviceId = '';
  String _role = 'tv';
  String _kind = '';
  String _name = '';
  String _app = '';
  String _version = '';
  String _build = '';
  bool _manualClose = false;
  bool _connecting = false;
  int _attempt = 0;
  int _seq = 0;
  String? _lastError;
  DateTime _lastFrameAt = DateTime.now();

  /// 连续这么久没有收到任何服务端帧，就认为连接已半开，主动重连。
  ///
  /// 客户端每 25 秒发一次应用层 ping，服务端会回 pong；60 秒相当于
  /// 连续错过两次 pong，避免把偶发延迟误判为断线。
  static const Duration _pongTimeout = Duration(seconds: 60);

  Stream<RealtimeConnectionState> get connectionState => _stateController.stream;
  Stream<RealtimeMessage> get messages => _messageController.stream;
  Stream<RealtimeEvent> get events => _eventController.stream;
  Stream<RealtimePresence> get presence => _presenceController.stream;
  Stream<String> get fatalErrors => _errorController.stream;
  Stream<void> get conversationsChanged => _conversationController.stream;

  /// 被控设备状态变化（roster / presence / state 任一更新时推送）。
  Stream<RealtimeDeviceState> get deviceStates => _deviceController.stream;

  RealtimeConnectionState get state => _state;
  bool get isConnected => _state == RealtimeConnectionState.connected;
  String get account => _account;
  String? get lastError => _lastError;
  Set<String> get onlineAccounts => Set<String>.unmodifiable(_online);

  /// 某设备当前已知状态；未知返回 null。
  RealtimeDeviceState? deviceInfoOf(String account) => _devices[account.trim()];

  /// 某账号是否在线。
  bool isOnline(String account) => _online.contains(account.trim());

  /// 连接并完成鉴权握手。失败抛 [RealtimeException]。
  ///
  /// [token] 为口令 MD5（与 HTTP 登录同一校验）；[deviceId] 供服务端
  /// 在在线日志/presence 中关联物理设备，可为空。
  /// [app] / [version] / [build] 为客户端标识（包名与版本构建号，见
  /// [ClientInfo]），随握手上报，服务端在线日志与 realtime.html 据此
  /// 区分不同控制端；断线重连时自动复用。
  ///
  /// 非鉴权类失败（网络/超时）会同时启动后台重连，恢复后自动转已连接。
  Future<void> connect({
    required String account,
    required String token,
    String deviceId = '',
    String role = 'tv',
    String kind = '',
    String? name,
    String app = '',
    String version = '',
    String build = '',
  }) async {
    _account = account.trim();
    _token = token;
    _deviceId = deviceId.trim();
    _role = role;
    _kind = kind.trim();
    _name = name ?? '';
    _app = app.trim();
    _version = version.trim();
    _build = build.trim();
    if (_account.isEmpty) {
      throw const RealtimeException(400, '账号为空');
    }
    _manualClose = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    _readyGate = Completer<bool>();
    final bool opened = await _open();
    if (!opened) {
      _readyGate = null;
      throw RealtimeException(-1, _lastError ?? '连接失败');
    }

    final bool ready = await _readyGate!.future
        .timeout(const Duration(seconds: 12), onTimeout: () => false);
    _readyGate = null;
    if (!ready) {
      throw RealtimeException(-2, _lastError ?? '握手失败');
    }
  }

  /// 主动断开（不再自动重连）。
  Future<void> disconnect() async {
    _manualClose = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _attempt = 0;
    _pingTimer?.cancel();
    _pingTimer = null;
    final StreamSubscription<dynamic>? sub = _subscription;
    final WebSocketChannel? channel = _channel;
    _subscription = null;
    _channel = null;
    _online.clear();
    // 主动断开意味着退出当前账号；保留账号会让上报模块把“手动退出”
    // 误判成临时断线，继续向旧账号发送心跳。
    _account = '';
    await sub?.cancel();
    try {
      await channel?.sink.close();
    } catch (_) {
      // 关闭失败不影响后续重连
    }
    _setState(RealtimeConnectionState.disconnected);
  }

  /// 发送文本；返回服务端是否受理（离队消息也算成功）。
  Future<bool> sendText({required String to, required String body}) async {
    if (!isConnected) return false;
    final String id = _nextId();
    final Completer<Map<String, dynamic>> completer =
        Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    _send(<String, dynamic>{'t': 'msg', 'id': id, 'to': to, 'body': body});
    try {
      final Map<String, dynamic> result = await completer.future
          .timeout(const Duration(seconds: 8), onTimeout: () => <String, dynamic>{});
      final bool ok = result['ok'] == true;
      if (ok) _conversationController.add(null);
      return ok;
    } finally {
      _pending.remove(id);
    }
  }

  /// 上报一条结构化事件；[to] 为空时只落库不投递。
  Future<bool> sendEvent({
    required String event,
    Map<String, dynamic>? data,
    String? to,
  }) async {
    if (!isConnected) return false;
    final String id = _nextId();
    final Completer<Map<String, dynamic>> completer =
        Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    _send(<String, dynamic>{
      't': 'event',
      'id': id,
      'event': event,
      if (to != null && to.isNotEmpty) 'to': to,
      'data': ?data,
    });
    try {
      final Map<String, dynamic> result = await completer.future
          .timeout(const Duration(seconds: 8), onTimeout: () => <String, dynamic>{});
      return result['ok'] == true;
    } finally {
      _pending.remove(id);
    }
  }

  /// 拉取与 [peer] 的历史消息（按时间升序）。
  Future<List<RealtimeMessage>> fetchHistory(String peer, {int limit = 50}) async {
    final Map<String, dynamic>? reply = await _request(
      <String, dynamic>{'t': 'history', 'peer': peer, 'limit': limit},
    );
    final List<dynamic> list = (reply?['messages'] as List<dynamic>?) ?? const <dynamic>[];
    return list
        .whereType<Map<String, dynamic>>()
        .map(RealtimeMessage.fromJson)
        .toList(growable: false);
  }

  /// 拉取会话列表（服务端聚合最近消息与未读数）。
  Future<List<RealtimeConversation>> fetchConversations() async {
    final Map<String, dynamic>? reply =
        await _request(<String, dynamic>{'t': 'conversations'});
    final List<dynamic> list = (reply?['items'] as List<dynamic>?) ?? const <dynamic>[];
    return list.whereType<Map<String, dynamic>>().map((Map<String, dynamic> json) {
      return RealtimeConversation(
        account: '${json['account'] ?? ''}',
        lastMessage: '${json['lastMessage'] ?? ''}',
        ts: (json['ts'] as num?)?.toInt() ?? 0,
        unread: (json['unread'] as num?)?.toInt() ?? 0,
      );
    }).toList(growable: false);
  }

  /// 拉取当前账号可见的结构化事件（按时间升序）。
  Future<List<RealtimeEvent>> fetchEvents({
    String? event,
    int? since,
    int limit = 100,
  }) async {
    final Map<String, dynamic>? reply = await _request(<String, dynamic>{
      't': 'events',
      if (event != null && event.isNotEmpty) 'event': event,
      'since': ?since,
      'limit': limit,
    });
    final List<dynamic> list =
        (reply?['items'] as List<dynamic>?) ?? const <dynamic>[];
    return list
        .whereType<Map<String, dynamic>>()
        .map(RealtimeEvent.fromJson)
        .toList(growable: false);
  }

  /// 标记与 [peer] 的会话已读（fire-and-forget）。
  void markRead(String peer) {
    if (!isConnected) return;
    _send(<String, dynamic>{'t': 'read', 'peer': peer});
    _conversationController.add(null);
  }

  /// 订阅某设备的实时状态；重连成功后自动补发 watch。
  ///
  /// 服务端会把该设备最近一次 `state` 立即回推，控制端无需再向设备要数据。
  Future<bool> watch(String account) async {
    final String target = account.trim();
    if (target.isEmpty) return false;
    _watched.add(target);
    if (!isConnected) return false;
    _send(<String, dynamic>{'t': 'watch', 'to': target});
    return true;
  }

  /// 取消订阅（离开遥控面板/会话时调用）。
  void unwatch(String account) {
    final String target = account.trim();
    if (target.isEmpty) return;
    _watched.remove(target);
    if (!isConnected) return;
    _send(<String, dynamic>{'t': 'unwatch', 'to': target});
  }

  /// 订阅与 [peer] 的合并会话线程（含 [also] 账号参与的往来）。
  ///
  /// 服务端立即回推快照（消息 + 事件混排，按时间升序），之后把匹配的新
  /// `msg`/`event` 帧推到 [messages]/[events] 流；重连成功后自动补发订阅。
  Future<List<RealtimeThreadItem>> watchThread(
    String peer, {
    List<String> also = const <String>[],
    int limit = 100,
  }) async {
    final String target = peer.trim();
    if (target.isEmpty) return const <RealtimeThreadItem>[];
    _watchedThreads[target] = also
        .map((String account) => account.trim())
        .where((String account) => account.isNotEmpty)
        .toList(growable: false);
    final Map<String, dynamic>? reply = await _request(<String, dynamic>{
      't': 'thread_watch',
      'peer': target,
      'also': also,
      'limit': limit,
    });
    final List<dynamic> list =
        (reply?['items'] as List<dynamic>?) ?? const <dynamic>[];
    return list
        .whereType<Map<String, dynamic>>()
        .map(RealtimeThreadItem.fromJson)
        .toList(growable: false);
  }

  /// 取消合并会话线程订阅（离开会话页时调用）。
  void unwatchThread(String peer) {
    final String target = peer.trim();
    if (target.isEmpty) return;
    _watchedThreads.remove(target);
    if (!isConnected) return;
    _send(<String, dynamic>{'t': 'thread_unwatch', 'peer': target});
  }

  /// 被控端上报自身状态：场景快照 + （仅变化时）完整频道列表。
  ///
  /// 服务端按账号缓存并转发给 watch 中的控制端；离线时无需重试，
  /// 重连后由上报方整体重发。
  Future<bool> sendState({
    required Map<String, Object?> scene,
    List<String>? channels,
    String? listVersion,
    Map<String, Object?>? playback,
  }) async {
    if (!isConnected) return false;
    _send(<String, dynamic>{
      't': 'state',
      'scene': scene,
      // null = 当前没有播放（非直播场景/播放器已销毁），服务端据此清空缓存。
      'playback': playback,
      if (channels != null)
        'channels': <String, dynamic>{
          'version': listVersion ?? '',
          'names': channels,
        },
    });
    return true;
  }

  Future<void> dispose() async {
    await disconnect();
    await _stateController.close();
    await _messageController.close();
    await _eventController.close();
    await _presenceController.close();
    await _errorController.close();
    await _conversationController.close();
    await _deviceController.close();
  }

  Future<bool> _open() async {
    if (_connecting) return false;
    _connecting = true;
    _manualClose = false;
    _setState(RealtimeConnectionState.connecting);
    try {
      final Uri uri = Uri.parse(_url).replace(queryParameters: <String, String>{
        'account': _account,
        'token': _token,
        'role': _role,
        if (_kind.isNotEmpty) 'kind': _kind,
        if (_deviceId.isNotEmpty) 'deviceId': _deviceId,
        if (_name.isNotEmpty) 'name': _name,
        if (_app.isNotEmpty) 'app': _app,
        if (_version.isNotEmpty) 'version': _version,
        if (_build.isNotEmpty) 'build': _build,
      });
      final WebSocketChannel channel = WebSocketChannel.connect(uri);
      await channel.ready.timeout(const Duration(seconds: 12));
      _channel = channel;
      _subscription = channel.stream.listen(
        _handleFrame,
        onError: _handleSocketError,
        onDone: _handleSocketDone,
        cancelOnError: false,
      );
      _attempt = 0;
      _lastFrameAt = DateTime.now();
      _startPing();
      Log.i('[RealtimeChannel] 已连接 $_url（$_account / $_role）');
      return true;
    } catch (e) {
      _lastError = '$e';
      Log.warn('[RealtimeChannel] 连接失败 $_url：$e');
      _readyGate?.complete(false);
      _setState(RealtimeConnectionState.disconnected);
      _scheduleReconnect();
      return false;
    } finally {
      _connecting = false;
    }
  }

  void _handleFrame(dynamic raw) {
    final Map<String, dynamic>? frame = _decode(raw);
    if (frame == null) return;
    // 任何服务端帧（包括 pong / presence）都说明链路有响应。
    _lastFrameAt = DateTime.now();
    switch (frame['t']) {
      case 'ready':
        final List<dynamic> online =
            (frame['online'] as List<dynamic>?) ?? const <dynamic>[];
        _online
          ..clear()
          ..addAll(online.map((dynamic e) => '$e'));
        // 在线端明细（含 kind）：刷新后首屏就能拿到各设备的类型与版本。
        final List<dynamic> roster =
            (frame['roster'] as List<dynamic>?) ?? const <dynamic>[];
        for (final dynamic raw in roster) {
          if (raw is! Map<String, dynamic>) continue;
          final String account = '${raw['account'] ?? ''}'.trim();
          if (account.isEmpty) continue;
          _upsertDevice(
            account,
            kind: '${raw['kind'] ?? ''}',
            app: '${raw['app'] ?? ''}',
            version: '${raw['version'] ?? ''}',
            build: '${raw['build'] ?? ''}',
          );
        }
        _lastError = null;
        _setState(RealtimeConnectionState.connected);
        if (!(_readyGate?.isCompleted ?? true)) _readyGate?.complete(true);
        // 重连后补发订阅：服务端会立即回推这些设备的缓存状态。
        for (final String target in _watched) {
          _send(<String, dynamic>{'t': 'watch', 'to': target});
        }
        for (final MapEntry<String, List<String>> entry
            in _watchedThreads.entries) {
          _send(<String, dynamic>{
            't': 'thread_watch',
            'peer': entry.key,
            'also': entry.value,
            'limit': 100,
          });
        }
        break;

      case 'state':
        final String from = '${frame['from'] ?? ''}'.trim();
        if (from.isEmpty) return;
        final dynamic rawScene = frame['scene'];
        final dynamic rawChannels = frame['channels'];
        // playback：键存在时必须处理（null = 已离开直播，清空）；
        // 键缺失视为「沿用上次」（旧服务端/旧设备不会带这个字段）。
        Map<String, Object?>? playback;
        if (frame.containsKey('playback')) {
          playback = _parsePlayback(frame['playback']);
        }
        List<String>? channels;
        String? listVersion;
        if (rawChannels is Map<String, dynamic>) {
          final dynamic names = rawChannels['names'];
          if (names is List) {
            channels = names.map((dynamic e) => '$e').toList(growable: false);
          }
          listVersion = '${rawChannels['version'] ?? ''}';
        }
        _upsertDevice(
          from,
          scene: rawScene is Map<String, dynamic>
              ? Map<String, Object?>.from(rawScene)
              : null,
          channels: channels,
          listVersion: listVersion,
          playback: playback,
        );
        break;

      case 'msg':
        final RealtimeMessage message = RealtimeMessage.fromJson(frame);
        if (message.body.isEmpty) return;
        _messageController.add(message);
        _conversationController.add(null);
        break;

      case 'event':
        final RealtimeEvent event = RealtimeEvent.fromJson(frame);
        if (event.event.isEmpty) return;
        _eventController.add(event);
        break;

      case 'result':
      case 'events':
      case 'history':
      case 'conversations':
      case 'thread':
        final String id = '${frame['id'] ?? ''}';
        final Completer<Map<String, dynamic>>? completer = _pending[id];
        if (completer != null && !completer.isCompleted) {
          completer.complete(frame);
        }
        break;

      case 'presence':
        final String account = '${frame['account'] ?? ''}';
        final bool online = frame['online'] == true;
        if (account.isEmpty) return;
        if (online) {
          _online.add(account);
        } else {
          _online.remove(account);
        }
        // presence 也带设备标识：上下线时同步刷新 kind，面板类型不会滞后。
        _upsertDevice(
          account,
          kind: '${frame['kind'] ?? ''}',
          app: '${frame['app'] ?? ''}',
          version: '${frame['version'] ?? ''}',
          build: '${frame['build'] ?? ''}',
        );
        _presenceController.add(RealtimePresence(account: account, online: online));
        break;

      case 'error':
        final int code = (frame['code'] as num?)?.toInt() ?? 0;
        final String msg = '${frame['msg'] ?? '未知错误'}';
        final String requestId = '${frame['id'] ?? ''}';
        final Completer<Map<String, dynamic>>? pending = _pending[requestId];
        if (pending != null && !pending.isCompleted) pending.complete(frame);
        _lastError = msg;
        Log.warn('[RealtimeChannel] 服务端错误 $code：$msg');
        if (code == 401 || code == 403 || code == 400) {
          _manualClose = true;
          _reconnectTimer?.cancel();
          _readyGate?.complete(false);
          _errorController.add(msg);
          _setState(RealtimeConnectionState.error);
          _closeSocket();
        }
        break;

      case 'pong':
        break;

      default:
        Log.i('[RealtimeChannel] 未处理帧: ${frame['t']}');
    }
  }

  void _handleSocketError(Object error) {
    _lastError = '$error';
    Log.warn('[RealtimeChannel] socket error：$error');
    _readyGate?.complete(false);
    _setState(RealtimeConnectionState.disconnected);
    _closeSocket();
    _scheduleReconnect();
  }

  void _handleSocketDone() {
    _channel = null;
    _subscription = null;
    _pingTimer?.cancel();
    _pingTimer = null;
    _online.clear();
    if (_manualClose) {
      _setState(RealtimeConnectionState.disconnected);
      return;
    }
    Log.i('[RealtimeChannel] 连接已关闭，准备重连');
    _readyGate?.complete(false);
    _setState(RealtimeConnectionState.disconnected);
    _scheduleReconnect();
  }

  /// 半开连接兜底：socket 还没触发 onDone，但已经收不到任何 pong/帧。
  void _handlePongTimeout() {
    if (_manualClose) return;
    _lastError = 'pong timeout';
    Log.warn('[RealtimeChannel] ${_pongTimeout.inSeconds}s 未收到服务端帧，主动重连');
    _readyGate?.complete(false);
    _setState(RealtimeConnectionState.disconnected);
    _closeSocket();
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_manualClose || _account.isEmpty) return;
    if (_reconnectTimer?.isActive ?? false) return;
    final int seconds = 1 << (_attempt > 5 ? 5 : _attempt);
    _attempt++;
    Log.i('[RealtimeChannel] ${seconds}s 后重连（第 $_attempt 次）');
    _reconnectTimer = Timer(Duration(seconds: seconds), () {
      _reconnectTimer = null;
      unawaited(_open());
    });
  }

  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      // 连接还没 ready 时由握手超时处理；不要在 connecting 状态误判。
      if (!isConnected) return;
      if (DateTime.now().difference(_lastFrameAt) >= _pongTimeout) {
        _handlePongTimeout();
        return;
      }
      _send(<String, dynamic>{'t': 'ping'});
    });
  }

  Future<Map<String, dynamic>?> _request(Map<String, dynamic> frame) async {
    if (!isConnected) return null;
    final String id = _nextId();
    final Completer<Map<String, dynamic>> completer =
        Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    _send(<String, dynamic>{...frame, 'id': id});
    try {
      return await completer.future
          .timeout(const Duration(seconds: 8), onTimeout: () => <String, dynamic>{});
    } finally {
      _pending.remove(id);
    }
  }

  void _send(Map<String, dynamic> frame) {
    final WebSocketChannel? channel = _channel;
    if (channel == null) return;
    try {
      channel.sink.add(jsonEncode(frame));
    } catch (e) {
      Log.warn('[RealtimeChannel] 发送失败：$e');
    }
  }

  void _closeSocket() {
    final StreamSubscription<dynamic>? sub = _subscription;
    final WebSocketChannel? channel = _channel;
    _subscription = null;
    _channel = null;
    _pingTimer?.cancel();
    _pingTimer = null;
    unawaited(sub?.cancel());
    unawaited(channel?.sink.close().catchError((Object _) {}));
    for (final Completer<Map<String, dynamic>> completer in _pending.values) {
      if (!completer.isCompleted) completer.complete(<String, dynamic>{});
    }
    _pending.clear();
  }

  Map<String, dynamic>? _decode(dynamic raw) {
    try {
      final dynamic decoded = jsonDecode('$raw');
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (e) {
      Log.warn('[RealtimeChannel] 非法帧：$e');
      return null;
    }
  }

  /// 合并一台设备的已知状态并广播给面板。
  ///
  /// 空字段一律沿用旧值（presence 可能只带 app，state 可能只带 scene）；
  /// 服务端未回显 kind 时用包名兜底（见 [kindOfApp]）。
  void _upsertDevice(
    String account, {
    String? kind,
    String? app,
    String? version,
    String? build,
    Map<String, Object?>? scene,
    List<String>? channels,
    String? listVersion,
    Map<String, Object?>? playback,
  }) {
    final String target = account.trim();
    if (target.isEmpty) return;
    final RealtimeDeviceState prev =
        _devices[target] ?? RealtimeDeviceState(account: target);
    final String nextApp = (app == null || app.isEmpty) ? prev.app : app;
    String nextKind = (kind == null || kind.isEmpty) ? prev.kind : kind;
    if (nextKind.isEmpty) nextKind = kindOfApp(nextApp);
    final RealtimeDeviceState next = prev.copyWith(
      kind: nextKind,
      app: nextApp,
      version: version == null || version.isEmpty ? null : version,
      build: build == null || build.isEmpty ? null : build,
      scene: scene,
      channels: channels,
      listVersion: listVersion == null || listVersion.isEmpty ? null : listVersion,
      playback: playback,
    );
    _devices[target] = next;
    if (!_deviceController.isClosed) _deviceController.add(next);
  }

  /// 解析 `state.playback`：null / 非对象一律当作「无播放」（空 map）。
  static Map<String, Object?> _parsePlayback(Object? raw) {
    if (raw is! Map) return const <String, Object?>{};
    return Map<String, Object?>.from(raw);
  }

  String _nextId() => '$_account-${DateTime.now().microsecondsSinceEpoch}-${++_seq}';

  void _setState(RealtimeConnectionState next) {
    if (_state == next) return;
    _state = next;
    if (!_stateController.isClosed) _stateController.add(next);
  }
}
