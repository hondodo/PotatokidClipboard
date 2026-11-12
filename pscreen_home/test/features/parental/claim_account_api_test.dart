import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/core/server/server_api.dart';
import 'package:pscreen_home/features/parental/data/parental_admin_api.dart';
import 'package:pscreen_screen/core/network/dio_manager.dart';

class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this.responseBody);

  final String responseBody;
  RequestOptions? last;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    last = options;
    return ResponseBody.fromString(
      responseBody,
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void useAdapter(_RecordingAdapter adapter) {
    final DioManager manager = DioManager();
    final HttpClientAdapter original = manager.dio.httpClientAdapter;
    manager.dio.httpClientAdapter = adapter;
    addTearDown(() => manager.dio.httpClientAdapter = original);
  }

  test('requestClaimTicket 命中 ticket 端点并解析凭证', () async {
    final _RecordingAdapter adapter = _RecordingAdapter(
      '{"code":0,"msg":"ok","data":{"claimToken":"clm.abc","expiresIn":600}}',
    );
    useAdapter(adapter);

    final String token = await const ParentalAdminApi().requestClaimTicket();

    expect(token, 'clm.abc');
    expect(adapter.last!.uri.path, '/api/admin/claim/ticket');
    expect(adapter.last!.method, 'POST');
  });

  test('claimAccount 提交家长号+自设口令+凭证，返回服务端确认的家长号', () async {
    // 新模型：口令由用户自设，服务端只回账号名，不再回传随机口令。
    final _RecordingAdapter adapter = _RecordingAdapter(
      '{"code":0,"msg":"ok","data":{"account":"mama_01","changed":["machines.json"]}}',
    );
    useAdapter(adapter);

    final ClaimAccountResult result = await const ParentalAdminApi().claimAccount(
      account: '  mama_01  ',
      password: 'self-chosen-123',
      claimToken: 'clm.abc',
    );

    expect(result.account, 'mama_01');
    // 结果口令回传请求值，统一持久化入口（不再依赖服务端下发）。
    expect(result.password, 'self-chosen-123');
    expect(adapter.last!.uri.path, '/api/admin/claim');
    expect(adapter.last!.method, 'POST');
    final String payload = adapter.last!.data.toString();
    expect(payload, contains('mama_01'));
    expect(payload, contains('self-chosen-123'));
    expect(payload, contains('clm.abc'));
  });

  test('服务端业务失败抛出带 msg 的异常', () async {
    final _RecordingAdapter adapter = _RecordingAdapter(
      '{"code":1,"msg":"凭证无效或已过期，请重新获取"}',
    );
    useAdapter(adapter);

    expect(
      () => const ParentalAdminApi().claimAccount(
        account: 'mama_01',
        password: 'self-chosen-123',
        claimToken: 'expired',
      ),
      throwsA(isA<ServerApiException>().having(
        (ServerApiException e) => e.message,
        'message',
        contains('凭证'),
      )),
    );
  });

  test('服务端未返回账号名时明确报错', () async {
    final _RecordingAdapter adapter =
        _RecordingAdapter('{"code":0,"msg":"ok","data":{}}');
    useAdapter(adapter);

    expect(
      () => const ParentalAdminApi().requestClaimTicket(),
      throwsA(isA<ServerApiException>()),
    );
  });

  test('changeParentPassword 命中改口令端点并提交新旧口令', () async {
    final _RecordingAdapter adapter = _RecordingAdapter(
      '{"code":0,"msg":"ok","data":{"account":"mama_01"}}',
    );
    useAdapter(adapter);

    await const ParentalAdminApi().changeParentPassword(
      currentPassword: 'old-pass',
      newPassword: 'new-pass-123',
    );

    expect(adapter.last!.uri.path, '/api/admin/parent-account/password');
    expect(adapter.last!.method, 'POST');
    final String payload = adapter.last!.data.toString();
    expect(payload, contains('old-pass'));
    expect(payload, contains('new-pass-123'));
  });

  test('loginRole 命中 /api/login 并解析角色（跨设备登录）', () async {
    final _RecordingAdapter adapter = _RecordingAdapter(
      '{"code":0,"msg":"登录成功","data":{"user":{"name":"mama_01","role":"parent"}}}',
    );
    useAdapter(adapter);

    final String role = await const ParentalAdminApi().loginRole(
      account: 'mama_01',
      passwordMd5: 'abc123md5',
    );

    expect(role, 'parent');
    expect(adapter.last!.uri.path, '/api/login');
    final String payload = adapter.last!.data.toString();
    expect(payload, contains('mama_01'));
    expect(payload, contains('abc123md5'));
  });
}
