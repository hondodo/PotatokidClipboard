import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_control/core/nim_client.dart';
import 'package:pscreen_control/features/send/application/send_cubit.dart';

/// Fake NimClient：记录 sendText 调用，可控失败。
class FakeNimClient implements NimClient {
  final List<(String, String)> sent = <(String, String)>[];
  bool failFirst = false;

  @override
  Future<bool> sendText({
    required String toAccount,
    required String text,
  }) async {
    if (failFirst) {
      failFirst = false; // 只让第一次失败
      sent.add((toAccount, text));
      return false;
    }
    sent.add((toAccount, text));
    return true;
  }

  @override
  Future<bool> init() async => true;
  @override
  Future<bool> autoLogin({required String account}) async => true;
  @override
  Future<bool> login({required String account, required String token}) async =>
      true;
  @override
  Future<void> logout() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late FakeNimClient nim;
  late SendCubit cubit;

  setUp(() {
    nim = FakeNimClient();
    cubit = SendCubit(nim: nim);
  });

  tearDown(() => cubit.close());

  test('初始状态：目标空、结果空', () {
    expect(cubit.state.targets, isEmpty);
    expect(cubit.state.sendResults, isEmpty);
    expect(cubit.state.isSending, isFalse);
  });

  test('toggleTarget 切换目标', () {
    cubit.toggleTarget('TV_001');
    expect(cubit.state.targets, contains('TV_001'));
    cubit.toggleTarget('TV_001');
    expect(cubit.state.targets, isNot(contains('TV_001')));
  });

  test('发送纯文本到多台，逐台结果', () async {
    cubit
      ..toggleTarget('TV_001')
      ..toggleTarget('TV_002');
    await cubit.sendPlainText('你好');
    expect(nim.sent.length, 2);
    expect(cubit.state.sendResults['TV_001'], isTrue);
    expect(cubit.state.sendResults['TV_002'], isTrue);
    expect(cubit.state.isSending, isFalse);
  });

  test('部分失败不影响其余，结果逐台记录', () async {
    nim.failFirst = true;
    cubit
      ..toggleTarget('TV_A')
      ..toggleTarget('TV_B');
    await cubit.sendPlainText('测试');
    expect(cubit.state.sendResults['TV_A'], isFalse);
    expect(cubit.state.sendResults['TV_B'], isTrue);
  });

  test('发送命令（JSON 信封）', () async {
    cubit.toggleTarget('TV_001');
    await cubit.sendCommand('volume_up');
    expect(nim.sent.single.$2, contains('"t":"cmd"'));
    expect(nim.sent.single.$2, contains('volume_up'));
  });

  test('无目标时发送不调用 SDK', () async {
    await cubit.sendPlainText('你好');
    expect(nim.sent, isEmpty);
    expect(cubit.state.sendResults, isEmpty);
  });

  test('clearResults 清空结果但保留目标', () async {
    cubit.toggleTarget('TV_001');
    await cubit.sendPlainText('你好');
    expect(cubit.state.sendResults, isNotEmpty);
    cubit.clearResults();
    expect(cubit.state.sendResults, isEmpty);
    expect(cubit.state.targets, contains('TV_001'));
  });

  test('逐台 emit：sendResults 随每台发送增长', () async {
    cubit
      ..toggleTarget('TV_001')
      ..toggleTarget('TV_002');
    final List<Map<String, bool>> snapshots = <Map<String, bool>>[];
    final sub = cubit.stream.listen((s) => snapshots.add(s.sendResults));
    await cubit.sendPlainText('你好');
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    // isSending:true 那次 emit 时 sendResults 仍空；随后每台一个非空快照
    final List<Map<String, bool>> nonEmpty =
        snapshots.where((m) => m.isNotEmpty).toList();
    expect(nonEmpty.length, greaterThanOrEqualTo(2));
    expect(nonEmpty.first.keys, ['TV_001']);
    expect(nonEmpty.last.keys, ['TV_001', 'TV_002']);
  });

  test('sendRaw 发送已构造 body', () async {
    cubit.toggleTarget('TV_001');
    await cubit.sendRaw('{"t":"cmd","name":"mute"}');
    expect(nim.sent.single.$2, '{"t":"cmd","name":"mute"}');
    expect(cubit.state.lastBody, '{"t":"cmd","name":"mute"}');
  });

  test('retryFailed 重发 lastBody 到失败目标', () async {
    nim.failFirst = true;
    cubit
      ..toggleTarget('TV_A')
      ..toggleTarget('TV_B');
    await cubit.sendPlainText('测试');
    expect(cubit.state.sendResults['TV_A'], isFalse);
    // 重试：now succeed
    final int before = nim.sent.length;
    await cubit.retryFailed(['TV_A']);
    expect(nim.sent.length, before + 1);
    expect(nim.sent.last.$1, 'TV_A');
    expect(nim.sent.last.$2, '测试');
    expect(cubit.state.sendResults['TV_A'], isTrue);
  });

  test('retryFailed 无 lastBody 时不发送', () async {
    await cubit.retryFailed(['TV_X']);
    expect(nim.sent, isEmpty);
  });
}
