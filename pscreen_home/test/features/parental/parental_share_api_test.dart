import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
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

/// 服务端写接口统一回 `data.view`，客户端不再二次请求 overview。
const String _viewResponse =
    '{"code":0,"msg":"ok","data":{"deviceId":"living","view":{'
    '"masters":[{"id":"c2","name":"大薯","sharedTo":["mama88"]}],'
    '"imported":[],"candidates":[]}}}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void useAdapter(_RecordingAdapter adapter) {
    final DioManager manager = DioManager();
    final HttpClientAdapter original = manager.dio.httpClientAdapter;
    manager.dio.httpClientAdapter = adapter;
    addTearDown(() => manager.dio.httpClientAdapter = original);
  }

  test('fetchShareView 用 query 传 deviceId，返回展开视图', () async {
    final _RecordingAdapter adapter = _RecordingAdapter(_viewResponse);
    useAdapter(adapter);

    final dynamic view = await const ParentalAdminApi().fetchShareView('living');

    expect(adapter.last!.uri.path, '/api/admin/parental/shared-view');
    expect(adapter.last!.uri.queryParameters, <String, String>{'deviceId': 'living'});
    expect(adapter.last!.uri.toString(), isNot(contains('%3F')));
    expect(view.masters.single.name, '大薯');
    expect(view.masters.single.sharedTo, <String>['mama88']);
  });

  test('setChildSharedTo 提交白名单并读回服务端结果', () async {
    final _RecordingAdapter adapter = _RecordingAdapter(_viewResponse);
    useAdapter(adapter);

    await const ParentalAdminApi().setChildSharedTo(
      'living',
      'c2',
      const <String>['mama88', 'grandpa88'],
    );

    expect(adapter.last!.uri.path, '/api/admin/parental/share-to');
    expect(adapter.last!.method, 'PUT');
    final String payload = adapter.last!.data.toString();
    expect(payload, contains('living'));
    expect(payload, contains('c2'));
    expect(payload, contains('mama88'));
  });

  test('addSharedRef / cancelSharedRef 命中各自端点并提交坐标', () async {
    final _RecordingAdapter adapter = _RecordingAdapter(_viewResponse);
    useAdapter(adapter);
    final ParentalAdminApi api = const ParentalAdminApi();

    await api.addSharedRef(
      'living',
      fromMachineId: 'bed',
      fromChildId: 'c11',
    );
    expect(adapter.last!.uri.path, '/api/admin/parental/shared');
    expect(adapter.last!.method, 'POST');
    expect(adapter.last!.data.toString(), contains('bed'));
    expect(adapter.last!.data.toString(), contains('c11'));

    await api.cancelSharedRef('living', 'bed:c11');
    expect(adapter.last!.uri.path, '/api/admin/parental/shared');
    expect(adapter.last!.method, 'DELETE');
    expect(adapter.last!.data.toString(), contains('bed:c11'));
  });

  test('overview 的 parentalShareView 随机器解析，非 tv 保持 null', () async {
    final _RecordingAdapter adapter = _RecordingAdapter(
      '{"code":0,"msg":"ok","data":{"machines":[{"id":"living","name":"客厅电视",'
      '"kind":"tv","owner":"o","parents":["AA_parent"],"commAccount":"tv1",'
      '"online":true,"parentalShareView":{"masters":[],"imported":[],'
      '"candidates":[{"machineId":"bed","machineName":"卧室电视","childId":"c11",'
      '"name":"逗逗","via":"shared-to-me"}]}},'
      '{"id":"home","name":"中控","kind":"home","owner":"o","parents":[],'
      '"commAccount":"home1","online":true}]}}',
    );
    useAdapter(adapter);

    final List<ParentalMachine> machines =
        await const ParentalAdminApi().fetchMachines();

    expect(machines, hasLength(2));
    expect(machines.first.shareView, isNotNull);
    expect(machines.first.shareView!.candidates.single.name, '逗逗');
    expect(machines.last.shareView, isNull);
  });
}
