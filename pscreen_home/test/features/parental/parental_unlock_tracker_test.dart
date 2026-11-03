import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/features/parental/application/parental_unlock_tracker.dart';

void main() {
  group('ParentalUnlockTracker 短码去重', () {
    late DateTime now;
    late ParentalUnlockTracker tracker;

    setUp(() {
      now = DateTime(2026, 11, 2, 10, 0, 0);
      tracker = ParentalUnlockTracker(
        handleTtl: const Duration(seconds: 60),
        now: () => now,
      );
    });

    test('同码双发只有第一条能开弹层', () {
      expect(tracker.tryAcquire('4821'), isTrue);
      expect(tracker.tryAcquire('4821'), isFalse);
      expect(tracker.activeCount, 1);
    });

    test('空码 / 空白码不开弹层', () {
      expect(tracker.tryAcquire(''), isFalse);
      expect(tracker.tryAcquire('   '), isFalse);
      expect(tracker.activeCount, 0);
    });

    test('不同短码互不影响', () {
      expect(tracker.tryAcquire('4821'), isTrue);
      expect(tracker.tryAcquire('9034'), isTrue);
      expect(tracker.activeCount, 2);
    });

    test('关闭后 TTL 内的迟到重复帧被吸收', () {
      expect(tracker.tryAcquire('4821'), isTrue);
      tracker.release('4821');
      expect(tracker.activeCount, 0);
      // 60s 窗口内重发同码（双发的第二条迟到到达）
      now = now.add(const Duration(seconds: 59));
      expect(tracker.tryAcquire('4821'), isFalse);
    });

    test('TTL 过期后同码可再次开弹层', () {
      expect(tracker.tryAcquire('4821'), isTrue);
      tracker.release('4821');
      now = now.add(const Duration(seconds: 61));
      expect(tracker.tryAcquire('4821'), isTrue);
    });

    test('短码带空白时按去空格后的值判重', () {
      expect(tracker.tryAcquire('4821'), isTrue);
      expect(tracker.tryAcquire(' 4821 '), isFalse);
    });
  });
}
