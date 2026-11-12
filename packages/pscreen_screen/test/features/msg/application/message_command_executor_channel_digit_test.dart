import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_screen/features/iptv/application/channel_info_provider.dart';
import 'package:pscreen_screen/features/iptv/application/channel_number_input_controller.dart';
import 'package:pscreen_screen/features/iptv/application/live_channel_controller.dart';
import 'package:pscreen_screen/features/iptv/domain/models/iptv_channel.dart';
import 'package:pscreen_screen/features/msg/application/message_command_executor.dart';

/// 音量 Fake（本组用例不触发音量命令）。
class _FakeVolume implements VolumeControl {
  @override
  Future<void> volumeUp() async {}

  @override
  Future<void> volumeDown() async {}

  @override
  Future<void> toggleMute() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MessageCommandExecutor executor;
  late LiveChannelController live;
  late ChannelNumberInputController input;

  setUp(() {
    live = LiveChannelController.instance;
    live.setCount(20); // 频道序号 1..20，用于超范围边界
    input = ChannelNumberInputController.instance;
    input.clear();
    executor = MessageCommandExecutor(
      volume: _FakeVolume(),
      liveChannel: live,
      channelInfo: ChannelInfoProvider.instance,
    );
  });

  tearDown(() {
    input.clear();
    live.setCount(0);
    ChannelInfoProvider.instance.setChannels(<IptvChannel>[]);
  });

  test('channel_digit：逐位累积回显，非法/越界参数不生效', () {
    expect(executor.execute('channel_digit', <String, dynamic>{'digit': 1}), isTrue);
    expect(input.digits, '1');
    expect(executor.execute('channel_digit', <String, dynamic>{'digit': 6}), isTrue);
    expect(input.digits, '16');

    // 缺参 / 非数字 / 超出 0~9 一律 false，不改变缓冲
    expect(executor.execute('channel_digit', null), isFalse);
    expect(executor.execute('channel_digit', <String, dynamic>{}), isFalse);
    expect(executor.execute('channel_digit', <String, dynamic>{'digit': '5'}), isFalse);
    expect(executor.execute('channel_digit', <String, dynamic>{'digit': 10}), isFalse);
    expect(executor.execute('channel_digit', <String, dynamic>{'digit': -1}), isFalse);
    expect(input.digits, '16');
  });

  test('channel_digit_clear：清空缓冲与超范围提示', () {
    executor.execute('channel_digit', <String, dynamic>{'digit': 9});
    executor.execute('channel_digit', <String, dynamic>{'digit': 9});
    // 99 > 20 → 立即超范围提示，缓冲被清
    expect(input.outOfRange, isTrue);
    expect(input.digits, '');

    expect(executor.execute('channel_digit_clear', null), isTrue);
    expect(input.outOfRange, isFalse);
    expect(input.visible, isFalse);
  });

  test('channel_digit_resolve：按当前缓冲立即结算切台；空缓冲不误报', () {
    // 空缓冲点「立即跳台」→ false，且不弹超范围
    expect(executor.execute('channel_digit_resolve', null), isFalse);
    expect(input.outOfRange, isFalse);

    live.setCount(20);
    executor.execute('channel_digit', <String, dynamic>{'digit': 1});
    executor.execute('channel_digit', <String, dynamic>{'digit': 6});
    expect(executor.execute('channel_digit_resolve', null), isTrue);
    // 16 落在 1..20 → 选中序号 value-1 = 15，缓冲已清
    expect(live.index, 15);
    expect(input.digits, '');
  });

  test('超范围号码按电视真实 count 判：input 阶段即拦截，不切台', () {
    executor.execute('channel_digit', <String, dynamic>{'digit': 9});
    // 第二位 9 → "99" > count(20)，input 立即清空缓冲并提示超范围
    executor.execute('channel_digit', <String, dynamic>{'digit': 9});
    expect(input.outOfRange, isTrue);
    expect(input.digits, '');
    // 缓冲已被超范围逻辑清空，此时「立即跳台」无事可做（false），索引不变
    expect(executor.execute('channel_digit_resolve', null), isFalse);
    expect(live.index, 0);
  });

  test('无频道时 channel_digit 不生效', () {
    live.setCount(0);
    expect(executor.execute('channel_digit', <String, dynamic>{'digit': 5}), isFalse);
  });
}
