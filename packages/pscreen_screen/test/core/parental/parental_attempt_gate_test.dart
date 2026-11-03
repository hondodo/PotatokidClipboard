import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_screen/core/parental/parental_attempt_gate.dart';
import 'package:pscreen_screen/core/utils/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 解锁防爆破闸门验证：连续错 5 次本地锁 60s、成功清零、
/// 计数与锁定持久化（重启不清；家长重置 `clearAllPersisted` 也不清）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DateTime now;

  setUp(() {
    now = DateTime(2026, 1, 1, 12);
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('连续错 5 次锁定 60s，到期自动放行', () async {
    final ParentalAttemptGate gate =
        ParentalAttemptGate.debugCreateForTest(() => now);
    for (int i = 1; i <= 4; i++) {
      await gate.recordFailure();
      expect(gate.failCount, i);
      expect(gate.locked, isFalse);
    }
    await gate.recordFailure(); // 第 5 次 → 触发锁定
    expect(gate.failCount, 0); // 触发后计数清零，下一轮从头计
    expect(gate.locked, isTrue);
    expect(gate.remainingLockSec, 60);

    now = now.add(const Duration(seconds: 30));
    expect(gate.locked, isTrue);
    expect(gate.remainingLockSec, 30);

    now = now.add(const Duration(seconds: 31)); // 共 61s
    expect(gate.locked, isFalse);
    expect(gate.remainingLockSec, 0);
  });

  test('验证成功清零连续失败计数与锁定', () async {
    final ParentalAttemptGate gate =
        ParentalAttemptGate.debugCreateForTest(() => now);
    await gate.recordFailure();
    await gate.recordFailure();
    expect(gate.failCount, 2);

    await gate.recordSuccess();
    expect(gate.failCount, 0);
    expect(gate.locked, isFalse);
  });

  test('持久化：重启（新实例）读回连续失败计数', () async {
    final ParentalAttemptGate gate1 =
        ParentalAttemptGate.debugCreateForTest(() => now);
    await gate1.recordFailure();
    await gate1.recordFailure();
    await gate1.recordFailure();
    expect(gate1.failCount, 3);

    final ParentalAttemptGate gate2 =
        ParentalAttemptGate.debugCreateForTest(() => now);
    await gate2.ensureLoaded();
    expect(gate2.failCount, 3);
    expect(gate2.locked, isFalse);
  });

  test('持久化：锁定态重启不清（新实例读回锁定与剩余秒）', () async {
    final ParentalAttemptGate gate1 =
        ParentalAttemptGate.debugCreateForTest(() => now);
    for (int i = 0; i < ParentalAttemptGate.maxFailures; i++) {
      await gate1.recordFailure();
    }
    expect(gate1.locked, isTrue);

    final ParentalAttemptGate gate2 =
        ParentalAttemptGate.debugCreateForTest(() => now);
    await gate2.ensureLoaded();
    expect(gate2.locked, isTrue);
    expect(gate2.remainingLockSec, 60);
    expect(gate2.failCount, 0);

    now = now.add(const Duration(seconds: 61));
    expect(gate2.locked, isFalse);
  });

  test('家长重置 clearAllPersisted 不清闸门键（parental_ 前缀豁免）', () async {
    final ParentalAttemptGate gate1 =
        ParentalAttemptGate.debugCreateForTest(() => now);
    await gate1.recordFailure();
    await gate1.recordFailure();

    await AppSettings.instance.clearAllPersisted();

    final ParentalAttemptGate gate2 =
        ParentalAttemptGate.debugCreateForTest(() => now);
    await gate2.ensureLoaded();
    expect(gate2.failCount, 2);
  });
}
