import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:potatokid_screen/features/iptv/presentation/components/touch_gesture_layer.dart';

/// 触屏手势层的纯手势识别回归保护。
///
/// 本测试不依赖 AppBloc/DI：只验证「pointer 手势 → 正确回调」的映射，
/// 以及 enabled/shouldAccept 两道门控。业务动作（切台/切源/呼出列表）由宿主
/// 传入回调，它们的正确性由既有控制器逻辑保证，遥控链路完全不经过本层。
void main() {
  const Offset center = Offset(400, 300);
  const Duration hold = Duration(milliseconds: 600);

  Widget buildLayer({
    required bool enabled,
    bool Function()? shouldAccept,
    required List<String> log,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            TouchGestureLayer(
              enabled: enabled,
              shouldAccept: shouldAccept ?? () => true,
              onTap: () => log.add('tap'),
              onSwipeUp: () => log.add('up'),
              onSwipeDown: () => log.add('down'),
              onSwipeLeft: () => log.add('left'),
              onSwipeRight: () => log.add('right'),
              onLongPress: () => log.add('long'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> tap(WidgetTester tester) async {
    final TestGesture g = await tester.startGesture(center);
    await g.up();
    await tester.pump();
  }

  Future<void> swipe(WidgetTester tester, Offset delta) async {
    final TestGesture g = await tester.startGesture(center);
    await g.moveBy(delta);
    await tester.pump();
    await g.up();
    await tester.pump();
  }

  testWidgets('单击分派 onTap', (WidgetTester tester) async {
    final List<String> log = <String>[];
    await tester.pumpWidget(buildLayer(enabled: true, log: log));
    await tap(tester);
    expect(log, <String>['tap']);
  });

  // 四个方向各自独立成用例：节流窗口基于真实时间（DateTime.now），
  // 同用例内连续两次滑动会被 250ms 节流吞掉，故每例只滑一次。
  testWidgets('上滑分派 onSwipeUp（上一台）', (WidgetTester tester) async {
    final List<String> log = <String>[];
    await tester.pumpWidget(buildLayer(enabled: true, log: log));
    await swipe(tester, const Offset(0, -100));
    expect(log, <String>['up']);
  });

  testWidgets('下滑分派 onSwipeDown（下一台）', (WidgetTester tester) async {
    final List<String> log = <String>[];
    await tester.pumpWidget(buildLayer(enabled: true, log: log));
    await swipe(tester, const Offset(0, 100));
    expect(log, <String>['down']);
  });

  testWidgets('左滑分派切上一源', (WidgetTester tester) async {
    final List<String> log = <String>[];
    await tester.pumpWidget(buildLayer(enabled: true, log: log));
    await swipe(tester, const Offset(-100, 0));
    expect(log, <String>['left']);
  });

  testWidgets('右滑分派切下一源', (WidgetTester tester) async {
    final List<String> log = <String>[];
    await tester.pumpWidget(buildLayer(enabled: true, log: log));
    await swipe(tester, const Offset(100, 0));
    expect(log, <String>['right']);
  });

  testWidgets('长按分派 onLongPress 且不误触发 tap', (
    WidgetTester tester,
  ) async {
    final List<String> log = <String>[];
    await tester.pumpWidget(buildLayer(enabled: true, log: log));
    final TestGesture g = await tester.startGesture(center);
    await tester.pump(hold);
    await g.up();
    await tester.pump();
    expect(log, <String>['long']);
  });

  testWidgets('enabled=false 时不分派任何手势', (WidgetTester tester) async {
    final List<String> log = <String>[];
    await tester.pumpWidget(buildLayer(enabled: false, log: log));
    await tap(tester);
    await swipe(tester, const Offset(0, -100));
    expect(log, isEmpty);
  });

  testWidgets('shouldAccept=false 时不分派手势（覆盖层门控二次确认）',
      (WidgetTester tester) async {
    final List<String> log = <String>[];
    await tester.pumpWidget(
      buildLayer(enabled: true, shouldAccept: () => false, log: log),
    );
    await tap(tester);
    await swipe(tester, const Offset(0, 100));
    expect(log, isEmpty);
  });

  testWidgets('位移未超 touchSlop 的微小移动仍判为单击', (
    WidgetTester tester,
  ) async {
    final List<String> log = <String>[];
    await tester.pumpWidget(buildLayer(enabled: true, log: log));
    await swipe(tester, const Offset(5, 5));
    expect(log, <String>['tap']);
  });
}
