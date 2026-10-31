import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:potatokid_clipboard/app/apis.dart';
import 'package:potatokid_clipboard/framework/net/dio/dio_manager.dart';
import 'package:potatokid_clipboard/framework/utils/app_log.dart';
import 'package:potatokid_clipboard/pages/home/tabs/clipboard/model/clipboard_item_model.dart';

/// 剪贴板 WebSocket 客户端。
///
/// 服务端 `/ws/clipboard` 用 Cookie 鉴权（与 HTTP 接口同一身份）：
/// 连接建立后立即回一帧 `clipboard_list` 快照，之后只在有新剪贴板落盘时
/// 推一帧 `clipboard_new`，用来替代原先每 2 秒一次的 `GET /api/clipboards` 轮询。
class ClipboardSocketService {
  ClipboardSocketService._();

  static final ClipboardSocketService instance = ClipboardSocketService._();

  static const String _path = '/ws/clipboard';
  static const Duration _heartbeatInterval = Duration(seconds: 30);
  static const Duration _maxRetryInterval = Duration(seconds: 30);

  final StreamController<List<ClipboardItemModel>> _snapshotController =
      StreamController<List<ClipboardItemModel>>.broadcast();
  final StreamController<ClipboardItemModel> _itemController =
      StreamController<ClipboardItemModel>.broadcast();
  final StreamController<bool> _connectedController =
      StreamController<bool>.broadcast();

  WebSocket? _socket;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  bool _enabled = false;
  bool _connecting = false;
  int _retrySeconds = 1;

  /// 连接代次：stop() 后使仍在握手中的旧连接作废
  int _session = 0;

  /// 连接成功时服务端回的快照（最近 20 条）
  Stream<List<ClipboardItemModel>> get onSnapshot =>
      _snapshotController.stream;

  /// 服务端推送的新增剪贴板
  Stream<ClipboardItemModel> get onNewItem => _itemController.stream;

  /// 连接状态变化（true=已连接）
  Stream<bool> get onConnectionChanged => _connectedController.stream;

  bool get isConnected => _socket != null;

  /// 建立连接（可重复调用，内部幂等）
  void start() {
    if (_enabled) return;
    _enabled = true;
    _retrySeconds = 1;
    _reconnectTimer?.cancel();
    _connect();
  }

  /// 断开连接并停止重连
  void stop() {
    final wasConnected = _socket != null;
    _enabled = false;
    _session++;
    _connecting = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _stopHeartbeat();
    final socket = _socket;
    _socket = null;
    socket?.close();
    if (wasConnected) _connectedController.add(false);
  }

  Future<void> _connect() async {
    if (!_enabled || _connecting || _socket != null) return;
    _connecting = true;
    final session = _session;
    try {
      final cookie = await _cookieHeader();
      if (session != _session) return; // 期间被 stop()
      if (cookie == null) {
        // 尚未登录或 Cookie 还没写入：稍后重试
        _connecting = false;
        _scheduleReconnect();
        return;
      }
      final socket = await WebSocket.connect(
        _wsUri().toString(),
        headers: {'Cookie': cookie},
      );
      if (session != _session || !_enabled) {
        // 期间被 stop()：丢弃这次握手结果
        socket.close();
        return;
      }
      _connecting = false;
      _socket = socket;
      _retrySeconds = 1;
      _connectedController.add(true);
      _startHeartbeat(socket);
      socket.listen(
        _handleMessage,
        onDone: _handleDisconnect,
        onError: (Object error) {
          Log.e('[ClipboardSocket] 连接异常: $error');
        },
        cancelOnError: false,
      );
      Log.d('[ClipboardSocket] 已连接 ${_wsUri()}');
    } catch (e) {
      if (session != _session) return;
      _connecting = false;
      Log.e('[ClipboardSocket] 连接失败: $e');
      _scheduleReconnect();
    }
  }

  void _handleDisconnect() {
    final wasConnected = _socket != null;
    _socket = null;
    _stopHeartbeat();
    if (wasConnected) _connectedController.add(false);
    Log.d('[ClipboardSocket] 连接断开，准备重连');
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (!_enabled || _reconnectTimer != null) return;
    final delay = Duration(
        seconds: _retrySeconds > _maxRetryInterval.inSeconds
            ? _maxRetryInterval.inSeconds
            : _retrySeconds);
    _retrySeconds *= 2;
    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      _connect();
    });
  }

  void _startHeartbeat(WebSocket socket) {
    _stopHeartbeat();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
      if (socket != _socket) return;
      try {
        socket.add(jsonEncode({'t': 'ping'}));
      } catch (e) {
        Log.e('[ClipboardSocket] 心跳发送失败: $e');
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void _handleMessage(dynamic raw) {
    try {
      final data = jsonDecode(raw.toString());
      if (data is! Map<String, dynamic>) return;
      final type = data['t'];
      if (type == 'clipboard_list') {
        final items = (data['clipboards'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ClipboardItemModel.fromJson)
            .toList();
        _snapshotController.add(items);
      } else if (type == 'clipboard_new') {
        final item = data['clipboard'];
        if (item is Map<String, dynamic>) {
          _itemController.add(ClipboardItemModel.fromJson(item));
        }
      } else if (type == 'error') {
        Log.e('[ClipboardSocket] 服务端错误: ${data['msg']}');
      }
      // pong 忽略
    } catch (e) {
      Log.e('[ClipboardSocket] 消息解析失败: $e');
    }
  }

  /// WebSocket 握手用的 Cookie；未登录时返回 null
  Future<String?> _cookieHeader() async {
    try {
      final cookie = await DioManager().getCookies();
      if (cookie.isEmpty || !cookie.contains('username=')) return null;
      return cookie;
    } catch (e) {
      Log.e('[ClipboardSocket] 读取 Cookie 失败: $e');
      return null;
    }
  }

  Uri _wsUri() {
    final base = Uri.parse(Hosts.baseHost);
    return base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: _path,
    );
  }
}
