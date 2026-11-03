import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_screen/core/media/kid_watch_timer_controller.dart';
import 'package:pscreen_screen/core/parental/parental_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

ChildProfile _child(
  String id, {
  int session = 0,
  int daily = 0,
  List<QuietHour> quiet = const <QuietHour>[],
}) =>
    ChildProfile(
      id: id,
      name: id,
      sessionLimitMin: session,
      dailyLimitMin: daily,
      quietHours: quiet,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('ParentalConfig 生效判定式与悬空 id', () {
    test('缺省（无 parental 字段）不启用——mode undefined 不误判', () {
      const ParentalConfig c = ParentalConfig();
      expect(c.enabled, isFalse);
    });

    test('mode=on 但 children 为空 → 不启用', () {
      const ParentalConfig c = ParentalConfig(mode: 'on');
      expect(c.enabled, isFalse);
    });

    test('mode=off 但有 children → 不启用（整层关闭）', () {
      const ParentalConfig c =
          ParentalConfig(mode: 'off', children: <ChildProfile>[
        ChildProfile(id: 'c1', name: 'A'),
      ]);
      expect(c.enabled, isFalse);
    });

    test('mode=on + children 非空 → 启用', () {
      const ParentalConfig c =
          ParentalConfig(mode: 'on', children: <ChildProfile>[
        ChildProfile(id: 'c1', name: 'A'),
      ]);
      expect(c.enabled, isTrue);
    });

    test('悬空 activeChildId：部分悬空过滤后保留剩余，全部悬空返回空', () {
      const ParentalConfig c = ParentalConfig(
        mode: 'on',
        activeChildIds: <String>['c1', 'ghost', 'c2'],
        children: <ChildProfile>[
          ChildProfile(id: 'c1', name: 'A'),
          ChildProfile(id: 'c2', name: 'B'),
        ],
      );
      expect(c.resolveActiveChildIds(c.activeChildIds), <String>['c1', 'c2']);
      expect(c.resolveActiveChildIds(<String>['ghost']), isEmpty);
    });
  });

  group('QuietHour', () {
    test('解析合法时段并往返序列化', () {
      final QuietHour? q = QuietHour.tryParse('22:00-06:00');
      expect(q, isNotNull);
      expect(q!.format(), '22:00-06:00');
      expect(QuietHour.tryParse(q.format()), isNotNull);
    });

    test('跨午夜判定：22:00-06:00 命中 23:30 与 05:00，不命中 12:00', () {
      final QuietHour q = QuietHour.tryParse('22:00-06:00')!;
      expect(q.contains(23 * 60 + 30), isTrue);
      expect(q.contains(5 * 60), isTrue);
      expect(q.contains(12 * 60), isFalse);
    });

    test('非法格式返回 null（坏条目忽略）', () {
      expect(QuietHour.tryParse(''), isNull);
      expect(QuietHour.tryParse('22-06'), isNull);
      expect(QuietHour.tryParse('ab:cd-06:00'), isNull);
      expect(QuietHour.tryParse('22:00-22:00'), isNull);
    });
  });

  group('KidWatchTimer 双计时', () {
    test('看满 session 阈值进锁屏（逐人判定）', () {
      fakeAsync((FakeAsync async) {
        DateTime now = DateTime(2026, 11, 2, 10, 0);
        final KidWatchTimerController t =
            KidWatchTimerController.debugCreateForTest(() => now);
        bool fired = false;
        t.onThresholdReached = () => fired = true;

        t.configure(
          enabled: true,
          profiles: <String, ChildProfile>{
            'c1': _child('c1', session: 1), // 1 分钟
          },
          quietHours: const <QuietHour>[],
          activeChildIds: const <String>['c1'],
        );
        t.setViewingScene(true);

        async.elapse(const Duration(seconds: 59));
        expect(t.locked, isFalse);
        expect(fired, isFalse);

        async.elapse(const Duration(seconds: 2));
        expect(t.locked, isTrue);
        expect(fired, isTrue);
        t.dispose();
      });
    });

    test('未到阈值不锁；限额为 0 = 该维度不启用', () {
      fakeAsync((FakeAsync async) {
        DateTime now = DateTime(2026, 11, 2, 10, 0);
        final KidWatchTimerController t =
            KidWatchTimerController.debugCreateForTest(() => now);
        t.configure(
          enabled: true,
          profiles: <String, ChildProfile>{'c1': _child('c1')}, // 限额全 0
          quietHours: const <QuietHour>[],
          activeChildIds: const <String>['c1'],
        );
        t.setViewingScene(true);
        async.elapse(const Duration(minutes: 10));
        expect(t.locked, isFalse);
        t.dispose();
      });
    });

    test('换人：仅新加入孩子从 0 起算，已在组合中的孩子 session 不清零', () {
      fakeAsync((FakeAsync async) {
        DateTime now = DateTime(2026, 11, 2, 10, 0);
        final KidWatchTimerController t =
            KidWatchTimerController.debugCreateForTest(() => now);
        t.configure(
          enabled: true,
          profiles: <String, ChildProfile>{
            'c1': _child('c1'),
            'c2': _child('c2'),
          },
          quietHours: const <QuietHour>[],
          activeChildIds: const <String>['c1'],
        );
        t.setViewingScene(true);
        async.elapse(const Duration(seconds: 30));
        expect(t.sessionSecOf('c1'), 30);

        // 加人（堵「加人续命」）：c1 保留 30s，c2 从 0 起算。
        t.configure(
          enabled: true,
          profiles: <String, ChildProfile>{
            'c1': _child('c1'),
            'c2': _child('c2'),
          },
          quietHours: const <QuietHour>[],
          activeChildIds: const <String>['c1', 'c2'],
        );
        expect(t.sessionSecOf('c1'), 30);
        expect(t.sessionSecOf('c2'), 0);

        async.elapse(const Duration(seconds: 10));
        expect(t.sessionSecOf('c1'), 40);
        expect(t.sessionSecOf('c2'), 10);
        t.dispose();
      });
    });

    test('场景口径：settings 不计入、屏保照常累计', () {
      fakeAsync((FakeAsync async) {
        DateTime now = DateTime(2026, 11, 2, 10, 0);
        final KidWatchTimerController t =
            KidWatchTimerController.debugCreateForTest(() => now);
        t.configure(
          enabled: true,
          profiles: <String, ChildProfile>{'c1': _child('c1')},
          quietHours: const <QuietHour>[],
          activeChildIds: const <String>['c1'],
        );
        t.setViewingScene(true);
        async.elapse(const Duration(seconds: 10));
        expect(t.sessionSecOf('c1'), 10);

        t.setViewingScene(false); // settings / 锁屏
        async.elapse(const Duration(seconds: 10));
        expect(t.sessionSecOf('c1'), 10); // 不计入

        t.setViewingScene(true); // 回到屏保/live
        async.elapse(const Duration(seconds: 5));
        expect(t.sessionSecOf('c1'), 15); // 累计
        t.dispose();
      });
    });

    test('退后台超 5 分钟重置 session，daily 不动', () {
      fakeAsync((FakeAsync async) {
        DateTime now = DateTime(2026, 11, 2, 10, 0);
        final KidWatchTimerController t =
            KidWatchTimerController.debugCreateForTest(() => now);
        t.configure(
          enabled: true,
          profiles: <String, ChildProfile>{'c1': _child('c1')},
          quietHours: const <QuietHour>[],
          activeChildIds: const <String>['c1'],
        );
        t.setViewingScene(true);
        async.elapse(const Duration(seconds: 30));
        expect(t.sessionSecOf('c1'), 30);
        expect(t.dailySecOf('c1'), 30);

        t.setAppForeground(false);
        now = now.add(const Duration(minutes: 6)); // 退后台 6 分钟
        t.setAppForeground(true);
        expect(t.sessionSecOf('c1'), 0); // session 重置
        expect(t.dailySecOf('c1'), 30); // daily 不动
        t.dispose();
      });
    });

    test('daily 到阈值锁屏后解锁写入放行窗口，窗口内不再立即回锁', () {
      fakeAsync((FakeAsync async) {
        DateTime now = DateTime(2026, 11, 2, 10, 0);
        final KidWatchTimerController t =
            KidWatchTimerController.debugCreateForTest(() => now);
        t.configure(
          enabled: true,
          profiles: <String, ChildProfile>{'c1': _child('c1', daily: 1)},
          quietHours: const <QuietHour>[],
          activeChildIds: const <String>['c1'],
        );
        t.setViewingScene(true);
        async.elapse(const Duration(seconds: 61));
        expect(t.locked, isTrue); // daily 到阈值

        t.unlock();
        expect(t.locked, isFalse);
        // 放行窗口内继续看，不因 daily 再锁。
        async.elapse(const Duration(seconds: 30));
        expect(t.locked, isFalse);
        t.dispose();
      });
    });

    test('持久化：重启（新实例 ensureLoaded）后 session/daily 不归零', () async {
      DateTime now = DateTime(2026, 11, 2, 10, 0);
      late KidWatchTimerController first;
      // 与生产初始化一致（ParentalModule.register 先 await timer.ensureLoaded()）：
      // 先落定 dateKey，否则首个 tick 误判「日期翻转」会多落盘一次，
      // 把 5 秒节流基准后移 1 秒，末次落盘停在 26 而非 30。
      first = KidWatchTimerController.debugCreateForTest(() => now);
      await first.ensureLoaded();
      fakeAsync((FakeAsync async) {
        first.configure(
          enabled: true,
          profiles: <String, ChildProfile>{'c1': _child('c1')},
          quietHours: const <QuietHour>[],
          activeChildIds: const <String>['c1'],
        );
        first.setViewingScene(true);
        // 逐秒推进注入时钟：每 5 秒触发一次落盘，末次落盘值应等于最终 session。
        for (int i = 0; i < 30; i++) {
          now = now.add(const Duration(seconds: 1));
          async.elapse(const Duration(seconds: 1));
        }
        expect(first.sessionSecOf('c1'), 30);
        // SharedPreferences 异步链可能挂在零延时 Timer 上，flushMicrotasks
        // 不会触发定时器——用 elapse(0) 排空（不影响 1 秒周期计时器）。
        async.elapse(Duration.zero);
        async.flushMicrotasks(); // 让 _save 落盘
      });

      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(KidWatchTimerController.storageKey);
      expect(raw, isNotNull);
      final Map<String, dynamic> data =
          Map<String, dynamic>.from(jsonDecode(raw!) as Map);
      final Map<String, dynamic> session =
          Map<String, dynamic>.from(data['sessionSecByChild'] as Map);
      expect(session['c1'], 30);

      // 模拟重启：新实例读回。
      final KidWatchTimerController rebooted =
          KidWatchTimerController.debugCreateForTest(() => now);
      await rebooted.ensureLoaded();
      expect(rebooted.sessionSecOf('c1'), 30);
      rebooted.dispose();
      first.dispose();
    });

    test('跨日：dateKey 翻转清零 daily', () {
      fakeAsync((FakeAsync async) {
        DateTime now = DateTime(2026, 11, 2, 23, 59, 50);
        final KidWatchTimerController t =
            KidWatchTimerController.debugCreateForTest(() => now);
        t.configure(
          enabled: true,
          profiles: <String, ChildProfile>{'c1': _child('c1')},
          quietHours: const <QuietHour>[],
          activeChildIds: const <String>['c1'],
        );
        t.setViewingScene(true);
        async.elapse(const Duration(seconds: 5));
        expect(t.dailySecOf('c1'), 5);

        now = DateTime(2026, 11, 3, 0, 0, 5); // 跨日
        async.elapse(const Duration(seconds: 1));
        // 翻转 tick 先清零 daily、同 tick 再 +1（新的一天已看 1 秒）。
        expect(t.dailySecOf('c1'), 1);
        expect(t.dailySecOf('c1'), lessThan(5)); // 已不包含昨日累计
        t.dispose();
      });
    });

    test('quietHours 命中即锁（并集语义由注入方保证）', () {
      fakeAsync((FakeAsync async) {
        // 注入一个落在禁看时段内的时刻。
        DateTime now = DateTime(2026, 11, 2, 23, 0, 0);
        final KidWatchTimerController t =
            KidWatchTimerController.debugCreateForTest(() => now);
        bool fired = false;
        t.onThresholdReached = () => fired = true;
        t.configure(
          enabled: true,
          profiles: <String, ChildProfile>{
            'c1': _child('c1', quiet: <QuietHour>[
              QuietHour.tryParse('22:00-06:00')!,
            ]),
          },
          quietHours: <QuietHour>[QuietHour.tryParse('22:00-06:00')!],
          activeChildIds: const <String>['c1'],
        );
        t.setViewingScene(true);
        expect(t.locked, isTrue);
        expect(fired, isTrue);
        t.dispose();
      });
    });

    test('disable（家长取消）后停计时并解锁', () {
      fakeAsync((FakeAsync async) {
        DateTime now = DateTime(2026, 11, 2, 10, 0);
        final KidWatchTimerController t =
            KidWatchTimerController.debugCreateForTest(() => now);
        t.configure(
          enabled: true,
          profiles: <String, ChildProfile>{'c1': _child('c1')},
          quietHours: const <QuietHour>[],
          activeChildIds: const <String>['c1'],
        );
        t.setViewingScene(true);
        async.elapse(const Duration(seconds: 10));
        expect(t.sessionSecOf('c1'), 10);

        t.configure(
          enabled: false,
          profiles: const <String, ChildProfile>{},
          quietHours: const <QuietHour>[],
          activeChildIds: const <String>[],
        );
        expect(t.enabled, isFalse);
        expect(t.locked, isFalse);
        // 停用时空选人移除了 c1，其 session 被清（防残留），且不再累加。
        expect(t.sessionSecOf('c1'), 0);
        async.elapse(const Duration(seconds: 10));
        expect(t.sessionSecOf('c1'), 0); // 停止累加
        t.dispose();
      });
    });
  });
}
