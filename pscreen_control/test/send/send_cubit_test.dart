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
}
