import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_screen/core/media/kid_watch_timer_controller.dart';
import 'package:pscreen_screen/core/parental/parental_config.dart';
import 'package:pscreen_screen/core/parental/parental_unlock_code_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 阶段 2「解锁短码」状态机验证：
/// 生成/60s 过期/一次性消费、同码双发（owner 直投 + 1000001）、
/// 锁屏边沿自动签发与解除作废、离线补发。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DateTime now;
  late List<Map<String, Object?>> sent;
  late bool online;

  /// 构造带记录型发送 Fake 的独立实例（不触碰全局单例）。
  ParentalUnlockCodeController make({String owner = 'owner001'}) {
    return ParentalUnlockCodeController.debugCreateForTest(
      now: () => now,
      deviceIdProvider: () async => 'dev-1',
      ownerAccountProvider: () => owner,
      sender: ({
        required String event,
        required String to,
        required Map<String, dynamic> data,
      }) async {
        sent.add(<String, Object?>{'event': event, 'to': to, 'data': data});
        return online;
      },
    );
  }

  setUp(() {
    now = DateTime(2026, 1, 1, 12);
    sent = <Map<String, Object?>>[];
    online = true;
  });

  test('issue 生成 6 位短码并同码双发（owner 直投 + 1000001）', () async {
    final ParentalUnlockCodeController c = make();
    final bool ok = await c.issue('session:c1');
    expect(ok, isTrue);
    expect(RegExp(r'^[1-9]\d{5}$').hasMatch(c.code!), isTrue);
    expect(c.active, isTrue);
    expect(c.remainingSec, inInclusiveRange(1, 60));
    expect(c.reason, 'session:c1');

    expect(sent.length, 2);
    expect(sent[0]['event'], ParentalUnlockCodeController.eventName);
    expect(sent[0]['to'], 'owner001');
    expect(sent[1]['to'], '1000001');
    // 两条 data 完全相同（含同一短码）→ 手机端按 code 去重。
    expect(sent[0]['data'], sent[1]['data']);
    final Map<String, dynamic> data = sent[0]['data']! as Map<String, dynamic>;
    expect(data['code'], c.code);
    expect(data['deviceId'], 'dev-1');
    expect(data['reason'], 'session:c1');
  });

  test('ownerAccount 缺省回退 1000001（①② 同账号双发）', () async {
    final ParentalUnlockCodeController c = make(owner: '');
    await c.issue('quietHours');
    expect(sent.length, 2);
    expect(sent[0]['to'], '1000001');
    expect(sent[1]['to'], '1000001');
    expect(sent[0]['data'], sent[1]['data']);
  });

  test('consume：错误码拒绝，正确码通过且一次性', () async {
    final ParentalUnlockCodeController c = make();
    await c.issue('daily:c1');
    final String code = c.code!;

    expect(c.consume('000000'), isFalse);
    expect(c.consumed, isFalse);
    expect(c.active, isTrue);

    expect(c.consume(code), isTrue);
    expect(c.consumed, isTrue);
    expect(c.active, isFalse);

    // 一次性：再次消费同一码拒绝。
    expect(c.consume(code), isFalse);
  });

  test('consume：60s 过期后拒绝（expired）', () async {
    final ParentalUnlockCodeController c = make();
    await c.issue('session:c1');
    final String code = c.code!;

    now = now.add(const Duration(seconds: 59));
    expect(c.active, isTrue);
    expect(c.remainingSec, 1);

    now = now.add(const Duration(seconds: 2)); // 共 61s
    expect(c.expired, isTrue);
    expect(c.consume(code), isFalse);
    expect(c.consumed, isFalse);
  });

  test('invalidate：作废后 code 清空且不可消费', () async {
    final ParentalUnlockCodeController c = make();
    await c.issue('session:c1');
    final String code = c.code!;
    c.invalidate();
    expect(c.code, isNull);
    expect(c.consume(code), isFalse);
    expect(c.active, isFalse);
  });

  test('watch：锁屏上升沿自动签发、解除下降沿作废', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'kid_watch_timer_v1':
          '{"dateKey":"2026-01-01","sessionSecByChild":{},'
          '"dailySecByChild":{"c1":99999},"unlockGraceUntilMs":{},'
          '"activeChildIds":["c1"]}',
    });
    final KidWatchTimerController timer =
        KidWatchTimerController.debugCreateForTest(() => now);
    await timer.ensureLoaded();
    // 挂载前先锁屏（daily 超限 + 无放行窗口）。
    timer.configure(
      enabled: true,
      profiles: <String, ChildProfile>{
        'c1': const ChildProfile(id: 'c1', name: '小宝', dailyLimitMin: 1),
      },
      quietHours: const <QuietHour>[],
      activeChildIds: const <String>['c1'],
    );
    expect(timer.locked, isTrue);

    final ParentalUnlockCodeController c = make();
    expect(sent, isEmpty);
    c.watch(timer);
    // 挂载时已锁（重启保持场景）→ 立即补发。
    await Future<void>.delayed(Duration.zero);
    expect(sent.length, 2);
    expect(c.active, isTrue);
    final String code = c.code!;

    // 解除（daily 放行窗口内不回锁）→ 下降沿作废旧码。
    timer.unlock();
    expect(timer.locked, isFalse);
    expect(c.code, isNull);
    expect(c.consume(code), isFalse);

    // 清理：停表 + 关模式，避免 ticker 残留。
    timer.configure(
      enabled: false,
      profiles: const <String, ChildProfile>{},
      quietHours: const <QuietHour>[],
      activeChildIds: const <String>[],
    );
    timer.clearAll();
    c.unwatch();
  });

  test('watch：未挂载/未锁不签发；重复挂同一计时器幂等', () async {
    final KidWatchTimerController timer =
        KidWatchTimerController.debugCreateForTest(() => now);
    final ParentalUnlockCodeController c = make();
    c.watch(timer);
    c.watch(timer); // 幂等：不叠加监听
    await Future<void>.delayed(Duration.zero);
    expect(sent, isEmpty);
    expect(c.code, isNull);
    c.unwatch();
  });

  test('flushPending：离线签发的短码登录后按原码补发', () async {
    online = false;
    final ParentalUnlockCodeController c = make();
    final bool ok = await c.issue('session:c1');
    expect(ok, isFalse); // 离线：两条均未受理
    expect(sent.length, 2);
    final String code = c.code!;

    online = true;
    final bool flushed = await c.flushPending();
    expect(flushed, isTrue);
    expect(sent.length, 4);
    expect(sent[2]['data'], sent[0]['data']); // 同码补发
    expect(sent[3]['to'], '1000001');

    // 已送达 → 再补发为空操作。
    expect(await c.flushPending(), isFalse);
    expect(sent.length, 4);

    // 过期后不再补发。
    now = now.add(const Duration(seconds: 61));
    expect(await c.flushPending(), isFalse);
    expect(sent.length, 4);
    expect(c.consume(code), isFalse);
  });
}
