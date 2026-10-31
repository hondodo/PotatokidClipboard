import 'dart:async';
import 'dart:convert';

import 'package:pscreen_screen/core/logging/log_service.dart';
import 'package:pscreen_home/core/network/ha_net_exceptions.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// HA 连接阶段
enum HaConnectionPhase {
  /// 未连接（初始 / 已断开且等待重试）
  disconnected,

  /// 连接中（首次或自动重连）
  connecting,

  /// 认证中（已发送访问令牌，等待 auth_ok）
  authenticating,

  /// 就绪（认证通过，可收发消息、已订阅状态事件）
  ready,

  /// 认证失败（令牌无效/未配置，不自动重试）
  authFailed,
}

/// 连接信息：阶段 + 失败原因 + 自动重试次数
class HaConnectionInfo {
  const HaConnectionInfo({
    required this.phase,
    this.message,
    this.retryCount = 0,
  });

  final HaConnectionPhase phase;
  final String? message;
  final int retryCount;

  bool get isReady => phase == HaConnectionPhase.ready;

  /// 是否处于自动重连流程中
  bool get isRetrying => retryCount > 0;

  /// 是否允许手动重试
  bool get canRetry =>
      phase == HaConnectionPhase.disconnected ||
      phase == HaConnectionPhase.authFailed;

  HaConnectionInfo copyWith({
    HaConnectionPhase? phase,
    String? message,
    int? retryCount,
  }) {
    return HaConnectionInfo(
      phase: phase ?? this.phase,
      message: message,
      retryCount: retryCount ?? this.retryCount,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is HaConnectionInfo &&
      other.phase == phase &&
      other.message == message &&
      other.retryCount == retryCount;

  @override
  int get hashCode => Object.hash(phase, message, retryCount);

  @override
  String toString() =>
      'HaConnectionInfo($phase, retry=$retryCount, message=$message)';
}

/// Home Assistant WebSocket 客户端（协议层，整个应用唯一的网络入口）。
///
/// 职责：
/// 1. 连接 + 认证（access_token）；
/// 2. 请求-响应：自增 id + Completer 配对，超时抛 [HaRequestException]；
/// 3. 事件推送：连接就绪后自动订阅 `state_changed`，通过 [stateChanged]
///    下发原始 `new_state` JSON（由各 feature 的 data 层反序列化为模型）；
/// 4. 断线自动重连：指数退避（1s → 2s → … → 30s 封顶），
///    认证失败（authFailed）不重试；
/// 5. 连接状态以 [HaConnectionInfo] 广播，供 ConnectionBloc 消费。
class HaWsClient {
  HaWsClient({
    required this.log,
    Duration requestTimeout = const Duration(seconds: 15),
    Duration heartbeatInterval = const Duration(seconds: 30),
    Duration pongTimeout = const Duration(seconds: 10),
  }) : _requestTimeout = requestTimeout,
       _heartbeatInterval = heartbeatInterval,
       _pongTimeout = pongTimeout;

  static const Duration _connectTimeout = Duration(seconds: 10);
  static const Duration _maxRetryDelay = Duration(seconds: 30);

  final LogService log;
  final Duration _requestTimeout;
  final Duration _heartbeatInterval;
  final Duration _pongTimeout;

  final StreamController<HaConnectionInfo> _infoController =
      StreamController<HaConnectionInfo>.broadcast();
  final StreamController<Map<String, dynamic>> _stateChangedController =
      StreamController<Map<String, dynamic>>.broadcast();
  final Map<int, Completer<Map<String, dynamic>>> _pending =
      <int, Completer<Map<String, dynamic>>>{};

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _channelSub;
  String _wsUrl = '';
  String _token = '';
  int _requestId = 0;
  int _retryCount = 0;

  /// 连续请求超时次数：达到阈值后主动重建 WebSocket。
  ///
  /// 仅靠 `onDone/onError` 无法发现半开连接（网络切换、Tailscale 断线后
  /// TCP 未及时关闭），此时状态仍是 ready，但所有请求都会超时。
  int _consecutiveRequestTimeouts = 0;

  /// 心跳：定期发 ping，超时未收到 pong 就强制重连。
  Timer? _heartbeatTimer;
  Timer? _pongTimer;
  int? _pingId;

  /// 连接代次：每次重建/销毁连接自增，旧连接的回调据此失效
  int _generation = 0;

  bool _manualClose = false;
  bool _disposed = false;
  bool _authSent = false;
  Completer<void>? _authCompleter;
  Timer? _retryTimer;
  HaConnectionInfo _info = const HaConnectionInfo(
    phase: HaConnectionPhase.disconnected,
  );

  /// 连接状态流
  Stream<HaConnectionInfo> watchConnection() => _infoController.stream;

  /// 当前连接状态
  HaConnectionInfo get connection => _info;

  /// 实体状态变化流（`state_changed` 事件的 `new_state` 原始 JSON）
  Stream<Map<String, dynamic>> get stateChanged =>
      _stateChangedController.stream;

  bool get isReady => _info.isReady;

  /// 发起连接；已连接或正在连接时幂等返回
  Future<void> connect({required String wsUrl, required String token}) async {
    _wsUrl = wsUrl.trim();
    _token = token.trim();
    _manualClose = false;
    _retryTimer?.cancel();
    if (_info.phase == HaConnectionPhase.connecting ||
        _info.phase == HaConnectionPhase.authenticating ||
        _info.phase == HaConnectionPhase.ready) {
      return;
    }
    _retryCount = 0;
    await _attempt();
  }

  /// 主动断开（不再自动重连）
  Future<void> disconnect() async {
    _manualClose = true;
    _retryTimer?.cancel();
    await _teardownChannel();
    _failPending(const HaDisconnectException('连接已关闭'));
    _emit(const HaConnectionInfo(phase: HaConnectionPhase.disconnected));
  }

  /// 释放资源（应用退出时调用）
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await disconnect();
    await _infoController.close();
    await _stateChangedController.close();
  }

  /// 发送请求，返回完整结果消息（含 success / result / error）
  Future<Map<String, dynamic>> request(
    String type, [
    Map<String, dynamic> params = const <String, dynamic>{},
  ]) {
    final channel = _channel;
    if (!_info.isReady || channel == null) {
      return Future<Map<String, dynamic>>.error(
        const HaDisconnectException('连接未就绪'),
      );
    }
    final id = ++_requestId;
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    channel.sink.add(
      jsonEncode(<String, dynamic>{'id': id, 'type': type, ...params}),
    );
    return completer.future.timeout(
      _requestTimeout,
      onTimeout: () {
        _pending.remove(id);
        _onRequestTimeout();
        throw HaRequestException(null, '请求超时：$type');
      },
    );
  }

  /// 请求超时累计：连续两次超时说明连接大概率已半开，主动重建。
  ///
  /// 单次超时可能是 HA 端慢查询（历史/统计），不立即断开；心跳会继续
  /// 兜底检测。成功响应会清零计数。
  void _onRequestTimeout() {
    _consecutiveRequestTimeouts++;
    if (_consecutiveRequestTimeouts < 2 || !_info.isReady) return;
    log.warn('HA 请求连续超时，强制重建 WebSocket');
    _handleChannelGone(_generation, const HaDisconnectException('请求连续超时'));
  }

  /// 调用 HA 服务（如 light.turn_on / switch.turn_off）
  Future<void> callService({
    required String domain,
    required String service,
    String? entityId,
    Map<String, dynamic> serviceData = const <String, dynamic>{},
  }) async {
    await request('call_service', <String, dynamic>{
      'domain': domain,
      'service': service,
      if (serviceData.isNotEmpty) 'service_data': serviceData,
      if (entityId != null && entityId.isNotEmpty)
        'target': <String, dynamic>{'entity_id': entityId},
    });
  }

  /// 明细历史（HA 只记录状态变化）。返回原始 `result`，由 data 层解析。
  ///
  /// `minimal_response` 返回紧凑结构 `{s, lu}`；`lu` 为 Unix 秒（浮点）。
  Future<Object?> historyDuringPeriod({
    required List<String> entityIds,
    required DateTime start,
    required DateTime end,
  }) async {
    final Map<String, dynamic> msg =
        await request('history/history_during_period', <String, dynamic>{
          'start_time': start.toUtc().toIso8601String(),
          'end_time': end.toUtc().toIso8601String(),
          'entity_ids': entityIds,
          'include_start_time_state': true,
          'significant_changes_only': true,
          'minimal_response': true,
          'no_attributes': true,
        });
    return msg['result'];
  }

  /// 长期统计（聚合）。返回原始 `result`，由 data 层解析。
  ///
  /// 返回 `start` 为 Unix 毫秒（整数），`mean/min/max` 为聚合值。
  Future<Object?> statisticsDuringPeriod({
    required List<String> statisticIds,
    required DateTime start,
    required DateTime end,
    required String period,
  }) async {
    final Map<String, dynamic> msg = await request(
      'recorder/statistics_during_period',
      <String, dynamic>{
        'start_time': start.toUtc().toIso8601String(),
        'end_time': end.toUtc().toIso8601String(),
        'statistic_ids': statisticIds,
        'period': period,
        'types': <String>['mean', 'min', 'max'],
      },
    );
    return msg['result'];
  }

  // ---------------------------------------------------------------- 连接

  Future<void> _attempt() async {
    if (_disposed || _manualClose) return;
    if (_wsUrl.isEmpty || _token.isEmpty) {
      _emit(
        const HaConnectionInfo(
          phase: HaConnectionPhase.authFailed,
          message: '未配置 AS_HOST / AS_KEY',
        ),
      );
      return;
    }

    _emit(
      HaConnectionInfo(
        phase: HaConnectionPhase.connecting,
        retryCount: _retryCount,
      ),
    );

    try {
      await _teardownChannel();
      final int gen = _generation;
      final WebSocketChannel channel = WebSocketChannel.connect(
        Uri.parse(_wsUrl),
      );
      await channel.ready.timeout(_connectTimeout);
      if (gen != _generation || _manualClose || _disposed) {
        await channel.sink.close();
        return;
      }

      _channel = channel;
      _authSent = false;
      final Completer<void> authCompleter = Completer<void>();
      _authCompleter = authCompleter;
      _channelSub = channel.stream.listen(
        (Object? raw) => _onMessage(raw, gen),
        onDone: () => _onChannelClosed(gen),
        onError: (Object e) => _onChannelError(e, gen),
        cancelOnError: false,
      );

      _emit(
        HaConnectionInfo(
          phase: HaConnectionPhase.authenticating,
          retryCount: _retryCount,
        ),
      );
      await authCompleter.future.timeout(_connectTimeout);

      if (gen != _generation || _manualClose || _disposed) return;
      _retryCount = 0;
      _consecutiveRequestTimeouts = 0;
      _emit(const HaConnectionInfo(phase: HaConnectionPhase.ready));
      _startHeartbeat(gen);
      unawaited(_subscribeStateChanges(gen));
    } catch (e) {
      if (_manualClose || _disposed) return;
      if (_info.phase == HaConnectionPhase.authFailed) return;
      await _teardownChannel();
      _retryCount += 1;
      log.warn('HA 连接失败（第 $_retryCount 次重试待启动）：$e');
      _emit(
        HaConnectionInfo(
          phase: HaConnectionPhase.disconnected,
          retryCount: _retryCount,
        ),
      );
      _scheduleRetry();
    }
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    final int shift = (_retryCount - 1).clamp(0, 5);
    Duration delay = Duration(seconds: 1 << shift);
    if (delay > _maxRetryDelay) delay = _maxRetryDelay;
    log.info('${delay.inSeconds}s 后重连 Home Assistant…');
    _retryTimer = Timer(delay, _attempt);
  }

  Future<void> _teardownChannel() async {
    _stopHeartbeat();
    _generation += 1;
    final StreamSubscription<dynamic>? sub = _channelSub;
    final WebSocketChannel? channel = _channel;
    _channelSub = null;
    _channel = null;
    try {
      await sub?.cancel();
    } catch (_) {}
    try {
      await channel?.sink.close();
    } catch (_) {}
  }

  // ------------------------------------------------------------ 心跳

  /// 连接就绪后启动心跳；上一轮心跳先取消，避免重复计时。
  void _startHeartbeat(int gen) {
    _stopHeartbeat();
    if (_heartbeatInterval <= Duration.zero) return;
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) => _sendPing(gen));
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _pongTimer?.cancel();
    _pongTimer = null;
    _pingId = null;
  }

  /// 发送一次 ping；上一次 pong 还没回来时不叠加新的 ping。
  void _sendPing(int gen) {
    if (gen != _generation || !_info.isReady) return;
    if (_pongTimer?.isActive ?? false) return;
    final WebSocketChannel? channel = _channel;
    if (channel == null) return;

    final int id = ++_requestId;
    _pingId = id;
    try {
      channel.sink.add(jsonEncode(<String, dynamic>{'id': id, 'type': 'ping'}));
    } catch (e) {
      log.warn('HA 心跳发送失败：$e');
      _handleChannelGone(gen, HaDisconnectException('心跳发送失败：$e'));
      return;
    }
    _pongTimer = Timer(_pongTimeout, () {
      if (gen != _generation || _pingId != id) return;
      log.warn('HA 心跳超时，强制重连');
      _pingId = null;
      _pongTimer = null;
      _handleChannelGone(gen, const HaDisconnectException('心跳超时'));
    });
  }

  void _onPong(int? id) {
    if (_pingId == null || (id != null && id != _pingId)) return;
    _pongTimer?.cancel();
    _pongTimer = null;
    _pingId = null;
  }

  Future<void> _subscribeStateChanges(int gen) async {
    try {
      await request('subscribe_events', <String, dynamic>{
        'event_type': 'state_changed',
      });
      if (gen == _generation) log.info('已订阅 state_changed 事件');
    } catch (e) {
      log.warn('订阅 state_changed 失败：$e');
    }
  }

  // ------------------------------------------------------------ 消息处理

  void _onMessage(Object? raw, int gen) {
    if (gen != _generation) return;
    final Map<String, dynamic> msg;
    try {
      msg = jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (e) {
      log.warn('收到无法解析的消息：$e');
      return;
    }

    switch (msg['type']) {
      case 'auth_required':
        if (!_authSent) {
          _authSent = true;
          _channel?.sink.add(
            jsonEncode(<String, dynamic>{
              'type': 'auth',
              'access_token': _token,
            }),
          );
        }
        break;
      case 'auth_ok':
        if (_authCompleter != null && !_authCompleter!.isCompleted) {
          _authCompleter!.complete();
        }
        break;
      case 'auth_invalid':
        final String message = msg['message'] as String? ?? '访问令牌无效';
        _stopHeartbeat();
        _emit(
          HaConnectionInfo(
            phase: HaConnectionPhase.authFailed,
            message: message,
          ),
        );
        if (_authCompleter != null && !_authCompleter!.isCompleted) {
          _authCompleter!.completeError(HaAuthException(message));
        }
        break;
      case 'result':
        _resolveRequest(msg);
        break;
      case 'pong':
        _onPong(_asInt(msg['id']));
        break;
      case 'event':
        _handleEvent(msg);
        break;
      default:
        log.debug('未处理的 WS 消息类型：${msg['type']}');
    }
  }

  void _resolveRequest(Map<String, dynamic> msg) {
    final int? id = _asInt(msg['id']);
    if (id == null) return;
    final Completer<Map<String, dynamic>>? completer = _pending.remove(id);
    if (completer == null || completer.isCompleted) return;
    _consecutiveRequestTimeouts = 0;
    if (msg['success'] == true) {
      completer.complete(msg);
    } else {
      final Object? rawError = msg['error'];
      final Map<Object?, Object?> error = rawError is Map
          ? rawError
          : const <Object?, Object?>{};
      completer.completeError(
        HaRequestException(_asInt(error['code']), error['message']?.toString()),
      );
    }
  }

  /// 宽松转 int：HA 的 id/code 多为 int，但个别消息会给字符串，解析失败返回 null。
  int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    return null;
  }

  void _handleEvent(Map<String, dynamic> msg) {
    final dynamic event = msg['event'];
    if (event is! Map) return;
    if (event['event_type'] != 'state_changed') return;
    final dynamic data = event['data'];
    if (data is! Map) return;
    final dynamic newState = data['new_state'];
    if (newState is! Map) return;
    if (_stateChangedController.isClosed) return;
    _stateChangedController.add(Map<String, dynamic>.from(newState));
  }

  // ------------------------------------------------------------ 断线处理

  void _onChannelClosed(int gen) {
    _handleChannelGone(gen, const HaDisconnectException('连接被关闭'));
  }

  void _onChannelError(Object error, int gen) {
    _handleChannelGone(gen, HaDisconnectException('$error'));
  }

  void _handleChannelGone(int gen, HaDisconnectException error) {
    if (gen != _generation || _manualClose || _disposed) return;
    if (_info.phase == HaConnectionPhase.authFailed ||
        _info.phase == HaConnectionPhase.disconnected) {
      return;
    }
    _stopHeartbeat();
    _consecutiveRequestTimeouts = 0;
    log.warn('与 Home Assistant 断开：${error.message ?? ''}');
    _failPending(error);
    _retryCount += 1;
    _emit(
      HaConnectionInfo(
        phase: HaConnectionPhase.disconnected,
        retryCount: _retryCount,
      ),
    );
    _scheduleRetry();
  }

  void _failPending(Object error) {
    final List<Completer<Map<String, dynamic>>> all =
        List<Completer<Map<String, dynamic>>>.from(_pending.values);
    _pending.clear();
    for (final completer in all) {
      if (!completer.isCompleted) completer.completeError(error);
    }
  }

  void _emit(HaConnectionInfo info) {
    if (info == _info) return;
    _info = info;
    if (_infoController.isClosed) return;
    _infoController.add(info);
  }
}
