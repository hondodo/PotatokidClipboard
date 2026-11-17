import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_screen/features/iptv/application/live_channel_controller.dart';

/// [LiveChannelController] 按频道名重定位的回归测试。
///
/// 场景来自实际 bug：后台改了频道列表顺序 / 缓存列表被网络列表替换后，
/// 控制器若死守旧序号，就会「序号没变、但那个序号已经是别的台」。
void main() {
  final LiveChannelController c = LiveChannelController.instance;

  setUp(() {
    // 单例无公开 reset：用 setCount(0) 把 index 复位，再清掉身份锚点。
    c.setCount(0);
    c.setPlayingName(null);
  });

  tearDown(() {
    c.setCount(0);
    c.setPlayingName(null);
  });

  group('relocateByName', () {
    test('无身份锚点时不改动序号', () {
      c.setCount(3);
      c.select(1);
      expect(c.index, 1);

      final bool moved = c.relocateByName(<String>['A', 'B', 'C']);
      expect(moved, isFalse);
      expect(c.index, 1);
    });

    test('列表重排后把序号校准回同一个频道名', () {
      c.setCount(3);
      // 旧列表：0=A 1=B 2=C；正在播 B（序号 1）。
      c.setPlayingName('B');
      c.select(1);
      expect(c.index, 1);

      // 新列表顺序变成 C B A，B 移到序号 1（此处不变，换个更明显的重排）：
      // 新列表 A C B，B 应在序号 2。
      final bool moved = c.relocateByName(<String>['A', 'C', 'B']);
      expect(moved, isTrue);
      expect(c.index, 2);
    });

    test('身份在新列表首位时也能定位（覆盖 index=0 的恢复场景）', () {
      c.setCount(3);
      c.setPlayingName('C');
      c.select(2);

      final bool moved = c.relocateByName(<String>['C', 'A', 'B']);
      expect(moved, isTrue);
      expect(c.index, 0);
    });

    test('序号本来就正确时不改动、不通知（返回 false）', () {
      c.setCount(3);
      c.setPlayingName('B');
      c.select(1);

      final bool moved = c.relocateByName(<String>['A', 'B', 'C']);
      expect(moved, isFalse);
      expect(c.index, 1);
    });

    test('频道已从新列表移除时保持序号，交由 setCount 夹边界', () {
      c.setCount(3);
      c.setPlayingName('C');
      c.select(2);

      // 新列表没有 C，只剩两项。
      c.setCount(2); // setCount 会把越界的 index 夹到 1
      final bool moved = c.relocateByName(<String>['A', 'B']);
      expect(moved, isFalse);
      expect(c.index, 1);
    });

    test('重定位只改序号，不触发播放提交', () {
      c.setCount(3);
      c.setPlayingName('B');
      c.select(1);

      int commits = 0;
      void listener() => commits++;
      c.onPlayCommit.addListener(listener);
      c.relocateByName(<String>['A', 'C', 'B']);
      c.onPlayCommit.removeListener(listener);

      expect(c.index, 2);
      expect(commits, 0);
    });

    test('空列表不改动', () {
      c.setCount(2);
      c.setPlayingName('A');
      c.select(0);
      expect(c.relocateByName(<String>[]), isFalse);
      expect(c.index, 0);
    });

    test('缓存列表恢复后网络列表替换（两阶段）仍停在同一个频道', () {
      // 阶段 1：缓存列表 0=A 1=B 2=C，恢复上次的 C（序号 2）并开播。
      c.setCount(3);
      c.setPlayingName('C'); // select 会触发 commit；此处直接设锚点模拟 _openCurrent
      c.select(2);
      expect(c.index, 2);

      // 阶段 2：网络列表到达，C 重排到序号 0，长度不变。
      c.setCount(3); // 同长度 → setCount 空操作
      final bool moved = c.relocateByName(<String>['C', 'A', 'B']);
      expect(moved, isTrue);
      expect(c.index, 0);
    });
  });

  test('setPlayingName 空串按清空处理', () {
    c.setCount(2);
    c.setPlayingName('A');
    expect(c.playingName, 'A');
    c.setPlayingName('');
    expect(c.playingName, isNull);
  });
}
