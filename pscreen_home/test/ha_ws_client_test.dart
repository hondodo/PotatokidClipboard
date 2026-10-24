import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/core/network/ha_net_exceptions.dart';
import 'package:pscreen_home/core/network/ha_ws_client.dart';
import 'package:pscreen_screen/core/logging/log_service.dart';

/// 极简 HA WebSocket 测试服务：完成 auth / 订阅握手，并按需响应 ping。
class _FakeHaServer {
  _FakeHaServer._(this._server, {required this.answerPing});

  final HttpServer _server;
  final bool answerPing;
  final List<WebSocket> _sockets = <WebSocket>[];

  String get url => 'ws://127.0.0.1:${_server.port}';

  static Future<_FakeHaServer> start({required bool answerPing}) async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final _FakeHaServer fake = _FakeHaServer._(server, answerPing: answerPing);
    server.listen(fake._handleRequest);
    return fake;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final WebSocket socket = await WebSocketTransformer.upgrade(request);
    _sockets.add(socket);
    socket.add(jsonEncode(<String, dynamic>{'type': 'auth_required'}));
    socket.listen(
      (dynamic raw) {
        final Map<String, dynamic> msg =
            jsonDecode(raw as String) as Map<String, dynamic>;
        switch (msg['type']) {
          case 'auth':
            socket.add(jsonEncode(<String, dynamic>{'type': 'auth_ok'}));
            break;
          case 'subscribe_events':
            socket.add(
              jsonEncode(<String, dynamic>{
                'id': msg['id'],
                'type': 'result',
                'success': true,
              }),
            );
            break;
          case 'ping':
            if (answerPing) {
              socket.add(
                jsonEncode(<String, dynamic>{'type': 'pong', 'id': msg['id']}),
              );
            }
            break;
          default:
            // get_states 等请求故意不响应，用于验证请求超时。
            break;
        }
      },
      onError: (Object _) {},
      cancelOnError: false,
    );
  }

  Future<void> close() async {
    for (final WebSocket socket in _sockets) {
      await socket.close();
    }
    await _server.close(force: true);
  }
}

void main() {
  group('HaWsClient 心跳', () {
    test('收到 pong 时保持 ready', () async {
      final _FakeHaServer server = await _FakeHaServer.start(answerPing: true);
      final HaWsClient client = HaWsClient(
        log: const LogService(),
        heartbeatInterval: const Duration(milliseconds: 40),
        pongTimeout: const Duration(milliseconds: 30),
      );
      addTearDown(() async {
        await client.dispose();
        await server.close();
      });

      await client.connect(wsUrl: server.url, token: 'token');
      expect(client.connection.phase, HaConnectionPhase.ready);

      await Future<void>.delayed(const Duration(milliseconds: 220));
      expect(client.connection.phase, HaConnectionPhase.ready);
    });

    test('收不到 pong 时判定半开连接并进入重连', () async {
      final _FakeHaServer server = await _FakeHaServer.start(answerPing: false);
      final HaWsClient client = HaWsClient(
        log: const LogService(),
        heartbeatInterval: const Duration(milliseconds: 40),
        pongTimeout: const Duration(milliseconds: 30),
      );
      addTearDown(() async {
        await client.dispose();
        await server.close();
      });

      final Future<HaConnectionInfo> disconnected = client
          .watchConnection()
          .firstWhere(
            (HaConnectionInfo info) =>
                info.phase == HaConnectionPhase.disconnected,
          )
          .timeout(const Duration(seconds: 2));

      await client.connect(wsUrl: server.url, token: 'token');
      expect(client.connection.phase, HaConnectionPhase.ready);
      await disconnected;
      expect(client.connection.phase, HaConnectionPhase.disconnected);
    });
  });

  group('HaWsClient 请求超时', () {
    test('连续两次请求超时会强制重建 WebSocket', () async {
      final _FakeHaServer server = await _FakeHaServer.start(answerPing: true);
      final HaWsClient client = HaWsClient(
        log: const LogService(),
        requestTimeout: const Duration(milliseconds: 40),
        heartbeatInterval: const Duration(seconds: 10),
      );
      addTearDown(() async {
        await client.dispose();
        await server.close();
      });

      final Future<HaConnectionInfo> disconnected = client
          .watchConnection()
          .firstWhere(
            (HaConnectionInfo info) =>
                info.phase == HaConnectionPhase.disconnected,
          )
          .timeout(const Duration(seconds: 2));

      await client.connect(wsUrl: server.url, token: 'token');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await expectLater(
        client.request('get_states'),
        throwsA(isA<HaRequestException>()),
      );
      await expectLater(
        client.request('get_states'),
        throwsA(isA<HaRequestException>()),
      );

      await disconnected;
      expect(client.connection.phase, HaConnectionPhase.disconnected);
    });
  });
}
