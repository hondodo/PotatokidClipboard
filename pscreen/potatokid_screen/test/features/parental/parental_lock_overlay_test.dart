import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:potatokid_screen/features/parental/presentation/widgets/parental_lock_overlay.dart';
import 'package:pscreen_screen/core/media/kid_watch_timer_controller.dart';
import 'package:pscreen_screen/core/parental/parental_config.dart';
import 'package:pscreen_screen/core/parental/parental_state_controller.dart';
import 'package:pscreen_screen/core/parental/parental_attempt_gate.dart';
import 'package:pscreen_screen/core/parental/parental_unlock_code_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 阶段 2 锁屏验证：
/// 1. 计时到阈值进锁屏 → 重新请求生成 6 位短码 → 家长验证层（算术兜底）解出
///    → 锁屏收起；
/// 2. `unlockMode = pin` → 家长验证层输入正确 PIN → 解锁收起。
///
/// 测试不跑 DI（无发送器），短码经「重新请求」本地生成；全局单例在
/// setUp/tearDown 间替换/还原，避免串扰。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final KidWatchTimerController timer = KidWatchTimerController.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await ParentalStateController.instance
        .saveLocalConfig(const ParentalConfig());
    ParentalUnlockCodeController.instance =
        ParentalUnlockCodeController.debugCreateForTest(
      now: DateTime.now,
      deviceIdProvider: () async => 'test-dev',
      ownerAccountProvider: () => '',
    );
    ParentalAttemptGate.instance.debugResetForTest();
    _resetTimer();
  });

  tearDown(() {
    ParentalUnlockCodeController.debugResetInstance();
    ParentalAttemptGate.instance.debugResetForTest();
    timer.onThresholdReached = null;
    _resetTimer();
  });

  testWidgets('到阈值进锁屏 → 重新请求短码 → 算术兜底解锁', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ParentalLockOverlay())),
    );
    expect(timer.onThresholdReached, isNotNull);
    expect(find.text('观看时间已到'), findsNothing);

    // 单次限额 1 分钟：进入计入场景后逐秒累加（testWidgets 的 FakeAsync
    // 会在 pump(duration) 时推进周期 ticker）。
    timer.configure(
      enabled: true,
      profiles: <String, ChildProfile>{
        'c1': const ChildProfile(id: 'c1', name: '小宝', sessionLimitMin: 1),
      },
      quietHours: const <QuietHour>[],
      activeChildIds: const <String>['c1'],
    );
    timer.setViewingScene(true);
    await tester.pump(const Duration(seconds: 61));
    await tester.pump();

    expect(timer.locked, isTrue);
    expect(find.text('观看时间已到'), findsOneWidget);
    // 无 DI（未挂计时器签发）→ 未生成短码，提供重新请求入口。
    expect(find.text('尚未生成解锁码'), findsOneWidget);

    await tester.tap(find.text('重新请求解锁码'));
    await tester.pump();
    final String codeText =
        tester.widget<Text>(find.textContaining('解锁码 ')).data!;
    expect(RegExp(r'^解锁码 \d{6}$').hasMatch(codeText), isTrue);
    expect(find.text('请在手机上确认解锁'), findsOneWidget);

    // 打开家长验证层（remote 模式：短码等待 + 算术断线兜底）。
    await tester.tap(find.text('家长验证解锁'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('家长验证'), findsOneWidget);
    // 验证层展示同一短码（锁屏页与其同时在树中，限定在 Dialog 内断言）。
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.text(codeText),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('断线兜底'), findsOneWidget);

    // 解算术题 → 验证通过 → 锁屏收起。
    final String question =
        tester.widget<Text>(find.textContaining(' + ')).data!;
    final Match m = RegExp(r'^(\d+) \+ (\d+) = \?$').firstMatch(question)!;
    final int sum = int.parse(m.group(1)!) + int.parse(m.group(2)!);
    await tester.tap(find.widgetWithText(OutlinedButton, '$sum'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(timer.locked, isFalse);
    expect(find.text('观看时间已到'), findsNothing);

    // 在 fakeAsync 区间内停表，避免周期 ticker 残留（tearDown 在区间之外）。
    _resetTimer();
  });

  testWidgets('pin 模式：家长验证层输入正确 PIN 解锁', (WidgetTester tester) async {
    await ParentalStateController.instance.saveLocalConfig(
      const ParentalConfig(
        mode: 'on',
        children: <ChildProfile>[
          ChildProfile(id: 'c1', name: '小宝', sessionLimitMin: 1),
        ],
        unlockMode: 'pin',
        pin: '1234',
      ),
    );
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ParentalLockOverlay())),
    );
    timer.configure(
      enabled: true,
      profiles: <String, ChildProfile>{
        'c1': const ChildProfile(id: 'c1', name: '小宝', sessionLimitMin: 1),
      },
      quietHours: const <QuietHour>[],
      activeChildIds: const <String>['c1'],
    );
    timer.setViewingScene(true);
    await tester.pump(const Duration(seconds: 61));
    await tester.pump();
    expect(timer.locked, isTrue);

    await tester.tap(find.text('家长验证解锁'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('输入 4 位 PIN'), findsOneWidget);
    expect(find.text('确认'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '1234');
    await tester.tap(find.text('确认'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));


    expect(timer.locked, isFalse);
    expect(find.text('观看时间已到'), findsNothing);

    _resetTimer();
  });
}

/// 复位全局单例（停表 + 清锁 + 清分账），避免用例间串扰。
void _resetTimer() {
  final KidWatchTimerController timer = KidWatchTimerController.instance;
  timer.configure(
    enabled: false,
    profiles: const <String, ChildProfile>{},
    quietHours: const <QuietHour>[],
    activeChildIds: const <String>[],
  );
  timer.clearAll();
}
