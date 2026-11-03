import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_screen/core/media/kid_watch_timer_controller.dart';
import 'package:pscreen_screen/core/parental/parental_config.dart';
import 'package:pscreen_screen/core/parental/parental_unlock_code_controller.dart';
import 'package:pscreen_screen/features/iptv/application/channel_info_provider.dart';
import 'package:pscreen_screen/features/iptv/application/live_channel_controller.dart';
import 'package:pscreen_screen/features/msg/application/message_command_executor.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 记录型音量 Fake（executor 构造必需；本组用例不触发音量命令）。
class _FakeVolume implements VolumeControl {
  @override
  Future<void> volumeUp() async {}

  @override
  Future<void> volumeDown() async {}

  @override
  Future<void> toggleMute() async {}
}

/// `parental_unlock` 命令校验（方案 §4.3）：短码匹配 + 60s 未过期 +
/// 一次性消费，全部满足才解除锁屏；任一失败按未知命令返回 false（不抛）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DateTime fakeNow;
  late MessageCommandExecutor executor;
  late KidWatchTimerController timer;

  /// 把全局锁屏计时器锁上。
  ///
  /// 用「daily 超限」而非 quietHours：unlock 写入 10 分钟放行窗口后
  /// 不会立即回锁，才能断言解锁成功。
  ///
  /// `dateKey` 必须按真实 `DateTime.now()` 计算——全局单例用真实时钟，
  /// 预置值与「今天」不一致会在 `ensureLoaded` 时把 daily 清零导致锁不上。
  Future<void> lockGlobalTimer() async {
    final DateTime realNow = DateTime.now();
    final String today = '${realNow.year.toString().padLeft(4, '0')}-'
        '${realNow.month.toString().padLeft(2, '0')}-'
        '${realNow.day.toString().padLeft(2, '0')}';
    SharedPreferences.setMockInitialValues(<String, Object>{
      'kid_watch_timer_v1': jsonEncode(<String, Object>{
        'dateKey': today,
        'sessionSecByChild': <String, int>{},
        'dailySecByChild': <String, int>{'c1': 99999},
        'unlockGraceUntilMs': <String, int>{},
        'activeChildIds': <String>['c1'],
      }),
    });
    timer = KidWatchTimerController.instance;
    await timer.ensureLoaded();
    timer.configure(
      enabled: true,
      profiles: <String, ChildProfile>{
        'c1': const ChildProfile(id: 'c1', name: '小宝', dailyLimitMin: 1),
      },
      quietHours: const <QuietHour>[],
      activeChildIds: const <String>['c1'],
    );
    expect(timer.locked, isTrue, reason: '前置：全局计时器已锁屏');
  }

  setUp(() async {
    fakeNow = DateTime(2026, 1, 1, 12);
    await lockGlobalTimer();
    // 换成注入假时钟的短码状态（过期用例需要拨时钟）。
    ParentalUnlockCodeController.instance =
        ParentalUnlockCodeController.debugCreateForTest(
      now: () => fakeNow,
      deviceIdProvider: () async => 'dev-1',
      ownerAccountProvider: () => 'owner001',
    );
    executor = MessageCommandExecutor(
      volume: _FakeVolume(),
      liveChannel: LiveChannelController.instance,
      channelInfo: ChannelInfoProvider.instance,
    );
  });

  tearDown(() {
    ParentalUnlockCodeController.debugResetInstance();
    timer.configure(
      enabled: false,
      profiles: const <String, ChildProfile>{},
      quietHours: const <QuietHour>[],
      activeChildIds: const <String>[],
    );
    timer.clearAll();
  });

  test('正确短码 → 解除锁屏', () async {
    await ParentalUnlockCodeController.instance.issue('daily:c1');
    final String code = ParentalUnlockCodeController.instance.code!;

    final bool ok = executor.execute('parental_unlock', <String, dynamic>{
      'code': code,
    });
    expect(ok, isTrue);
    expect(timer.locked, isFalse);
  });

  test('错误码 / 缺 code / 非字符串 → false 且保持锁屏', () async {
    await ParentalUnlockCodeController.instance.issue('daily:c1');

    expect(executor.execute('parental_unlock', null), isFalse);
    expect(executor.execute('parental_unlock', <String, dynamic>{}), isFalse);
    expect(
      executor.execute('parental_unlock', <String, dynamic>{'code': 123456}),
      isFalse,
    );
    expect(
      executor.execute('parental_unlock', <String, dynamic>{'code': '000000'}),
      isFalse,
    );
    expect(timer.locked, isTrue);
  });

  test('过期短码（超 60s）→ false 且保持锁屏', () async {
    await ParentalUnlockCodeController.instance.issue('daily:c1');
    final String code = ParentalUnlockCodeController.instance.code!;

    fakeNow = fakeNow.add(const Duration(seconds: 61));
    final bool ok = executor.execute('parental_unlock', <String, dynamic>{
      'code': code,
    });
    expect(ok, isFalse);
    expect(timer.locked, isTrue);
  });

  test('一次性：消费成功后同一短码再次下发 → false', () async {
    await ParentalUnlockCodeController.instance.issue('daily:c1');
    final String code = ParentalUnlockCodeController.instance.code!;

    expect(
      executor.execute('parental_unlock', <String, dynamic>{'code': code}),
      isTrue,
    );
    expect(timer.locked, isFalse);

    expect(
      executor.execute('parental_unlock', <String, dynamic>{'code': code}),
      isFalse,
    );
  });
}
