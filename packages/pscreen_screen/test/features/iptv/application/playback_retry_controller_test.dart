import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_screen/features/iptv/application/playback_retry_controller.dart';

/// 被测控制器 + 各回调的调用记录。
class _Harness {
  _Harness({
    required int sourceCount,
    PlaybackRouteFn? route,
    bool Function()? isActive,
    Duration cooldown = const Duration(milliseconds: 700),
  }) {
    controller = PlaybackRetryController(
      sourceCount: () => sourceCount,
      open: (int index) async => opened.add(index),
      onEnterRetry: retries.add,
      retryWithRoute: route,
      onBackoff: (int round, Duration wait) => backoffs.add((round, wait)),
      onSourceChanged: (int index, String reason) => sourceChanges.add((index, reason)),
      isActive: isActive,
      cooldown: cooldown,
    );
  }

  late final PlaybackRetryController controller;

  /// 每次 open 的源序号（按发生顺序）。
  final List<int> opened = <int>[];

  /// 每次进入重试的原因（失败现场）。
  final List<String> retries = <String>[];

  /// 换源回调：(新源序号, 触发原因)。
  final List<(int, String)> sourceChanges = <(int, String)>[];

  /// 退避回调：(第几轮, 等待时长)。
  final List<(int, Duration)> backoffs = <(int, Duration)>[];
}

List<Duration> _waits(_Harness h) => h.backoffs.map(((int, Duration) e) => e.$2).toList(growable: false);

void main() {
  group('多源回退', () {
    test('失败按 0→1→2→0 循环，满一轮先退避 1s 再回第一个源', () {
      fakeAsync((FakeAsync async) {
        final _Harness h = _Harness(sourceCount: 3);

        h.controller.handleIssue(reason: 'r1');
        async.flushMicrotasks();
        expect(h.opened, <int>[1]);
        expect(h.controller.sourceIndex, 1);

        h.controller.handleIssue(reason: 'r2');
        async.flushMicrotasks();
        expect(h.opened, <int>[1, 2]);

        // 第三个源也失败 = 满一轮 → 退避 1s 后回源 0。
        h.controller.handleIssue(reason: 'r3');
        async.flushMicrotasks();
        expect(h.backoffs, <(int, Duration)>[(1, Duration(seconds: 1))]);
        expect(h.opened, <int>[1, 2]); // 退避未结束，还没有新的 open
        async.elapse(const Duration(seconds: 1));
        expect(h.opened, <int>[1, 2, 0]);
        expect(h.controller.sourceIndex, 0);
        expect(h.controller.failedRounds, 1);

        // 失败现场在换源之前上报，原因与新源号如实透传。
        expect(h.retries, <String>['r1', 'r2', 'r3']);
        expect(h.sourceChanges, <(int, String)>[
          (1, 'r1'),
          (2, 'r2'),
          (0, 'r3'),
        ]);
      });
    });

    test('单源频道每次失败都算一轮并退避，源号不变', () {
      fakeAsync((FakeAsync async) {
        final _Harness h = _Harness(sourceCount: 1);
        for (int i = 0; i < 3; i++) {
          h.controller.handleIssue();
          async.flushMicrotasks();
          async.elapse(const Duration(seconds: 30));
        }
        expect(h.opened, <int>[0, 0, 0]);
        expect(h.controller.sourceIndex, 0);
        expect(h.controller.failedRounds, 3);
        expect(_waits(h), <Duration>[Duration(seconds: 1), Duration(seconds: 2), Duration(seconds: 4)]);
        expect(h.retries.length, 3);
      });
    });
  });

  group('退避', () {
    test('轮数退避 1s→2s→4s→8s 并在 8s 封顶', () {
      fakeAsync((FakeAsync async) {
        final _Harness h = _Harness(sourceCount: 1);
        for (int i = 0; i < 5; i++) {
          h.controller.handleIssue();
          async.flushMicrotasks();
          async.elapse(const Duration(seconds: 30));
        }
        expect(_waits(h), <Duration>[
          Duration(seconds: 1),
          Duration(seconds: 2),
          Duration(seconds: 4),
          Duration(seconds: 8),
          Duration(seconds: 8),
        ]);
        expect(h.controller.failedRounds, 5);
      });
    });

    test('播放成功 resetRound 后退避重新从 1s 起算', () {
      fakeAsync((FakeAsync async) {
        final _Harness h = _Harness(sourceCount: 1);
        h.controller.handleIssue();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 30));
        h.controller.handleIssue();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 30));
        expect(_waits(h).last, const Duration(seconds: 2));

        h.controller.resetRound(); // 播放成功
        expect(h.controller.failedRounds, 0);
        h.controller.handleIssue();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 30));
        expect(_waits(h).last, const Duration(seconds: 1));
      });
    });

    test('退避等待中换台（resetForChannel）→ 过期回退作废，不顶掉新频道', () {
      fakeAsync((FakeAsync async) {
        final _Harness h = _Harness(sourceCount: 1);
        h.controller.handleIssue();
        async.flushMicrotasks(); // 进入 1s 退避等待
        expect(h.backoffs, hasLength(1));

        h.controller.resetForChannel(0); // 用户切台
        async.elapse(const Duration(seconds: 5));
        expect(h.opened, isEmpty); // 过期回退被丢弃
        expect(h.controller.isHandlingFailure, isFalse);
      });
    });

    test('退避等待中手动换源（setSource）→ 过期回退作废', () {
      fakeAsync((FakeAsync async) {
        final _Harness h = _Harness(sourceCount: 2);
        h.controller.handleIssue();
        async.flushMicrotasks(); // 失败源0 → open(1)
        h.controller.handleIssue();
        async.flushMicrotasks(); // 失败源1 → 满一轮 → 进入退避
        expect(h.backoffs, hasLength(1));

        h.controller.setSource(0); // 用户手动切源
        async.elapse(const Duration(seconds: 5));
        expect(h.opened, <int>[1]); // 不再有新的 open
        expect(h.controller.isHandlingFailure, isFalse);
      });
    });
  });

  group('冷却与并发抑制', () {
    test('open 后 700ms 内的失败被冷却过滤，bypass 可跳过', () async {
      final _Harness h = _Harness(sourceCount: 3);
      h.controller.markOpen();

      await h.controller.handleIssue(reason: 'stale');
      expect(h.retries, isEmpty); // 冷却内 → 视为旧源残留
      expect(h.opened, isEmpty);

      await h.controller.handleIssue(reason: 'real', bypassCooldown: true);
      expect(h.retries, <String>['real']);
      expect(h.opened, <int>[1]);
    });

    test('冷却到期后正常进入重试', () async {
      final _Harness h = _Harness(sourceCount: 3, cooldown: const Duration(milliseconds: 50));
      h.controller.markOpen();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await h.controller.handleIssue(reason: 'late');
      expect(h.retries, <String>['late']);
    });

    test('上一次失败未处理完时，后续失败被 busy 抑制', () {
      fakeAsync((FakeAsync async) {
        final _Harness h = _Harness(sourceCount: 3);
        h.controller.handleIssue(reason: 'a');
        h.controller.handleIssue(reason: 'b'); // busy → 立即丢弃
        async.flushMicrotasks();
        expect(h.retries, <String>['a']);
        expect(h.opened, <int>[1]);
      });
    });

    test('isActive=false（已销毁）时不处理失败', () async {
      final _Harness h = _Harness(sourceCount: 3, isActive: () => false);
      await h.controller.handleIssue(reason: 'x', bypassCooldown: true);
      expect(h.retries, isEmpty);
      expect(h.opened, isEmpty);
    });
  });

  group('路由注入（代理池抽象）', () {
    test('路由可用 → 同一源经路由重开，状态机不再换源', () async {
      final List<int> routeAsked = <int>[];
      final _Harness h = _Harness(
        sourceCount: 3,
        route: (int failedIndex, String reason) async {
          routeAsked.add(failedIndex);
          return true;
        },
      );
      await h.controller.handleIssue(reason: 'boom', bypassCooldown: true);
      expect(routeAsked, <int>[0]);
      expect(h.retries, <String>['boom']); // 失败现场仍先上报
      expect(h.opened, isEmpty); // 重开由路由侧自己完成
      expect(h.controller.sourceIndex, 0);
      expect(h.controller.isHandlingFailure, isFalse);
    });

    test('路由不可用 → 回落换源回退', () async {
      final _Harness h = _Harness(
        sourceCount: 3,
        route: (int failedIndex, String reason) async => false,
      );
      await h.controller.handleIssue(reason: 'boom', bypassCooldown: true);
      expect(h.opened, <int>[1]);
      expect(h.controller.sourceIndex, 1);
    });

    test('未注入路由 → 直接换源回退', () async {
      final _Harness h = _Harness(sourceCount: 3);
      await h.controller.handleIssue(reason: 'boom', bypassCooldown: true);
      expect(h.opened, <int>[1]);
    });
  });

  group('起播源与世代号', () {
    test('resetForChannel 指定起播源并开启全新一轮', () async {
      final _Harness h = _Harness(sourceCount: 4);
      h.controller.resetForChannel(2);
      expect(h.controller.sourceIndex, 2);
      expect(h.controller.failedRounds, 0);
      // 源2 失败：4 个源只试了 1 个，不满一轮 → 直接回退到下一个源。
      await h.controller.handleIssue(reason: 'x', bypassCooldown: true);
      expect(h.opened, <int>[3]); // (2+1)%4
    });

    test('退避期间换台后，旧世代的回退被丢弃', () {
      fakeAsync((FakeAsync async) {
        final _Harness h = _Harness(sourceCount: 1);
        h.controller.handleIssue(reason: 'x', bypassCooldown: true);
        async.flushMicrotasks();
        expect(h.backoffs, hasLength(1)); // 单源：失败即满一轮 → 进入退避

        h.controller.resetForChannel(0); // 切台（推进世代号）
        async.elapse(const Duration(seconds: 5));
        expect(h.opened, isEmpty);
        expect(h.controller.isHandlingFailure, isFalse);
      });
    });
  });
}
