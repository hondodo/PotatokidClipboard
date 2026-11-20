import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pscreen_home/features/home/presentation/components/span_reorderable_grid.dart';

void main() {
  testWidgets('长按 500ms 进入编辑态并显示完成按钮，点完成退出', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SpanReorderableGrid<int>(
          items: const <int>[0, 1, 2, 3],
          spanOf: (int i) => const CardGridSpan(),
          keyOf: (int i) => 'k$i',
          itemBuilder: (BuildContext context, int index, int item) =>
              Container(key: ValueKey<int>(item), color: Colors.teal),
          onReorder: (_) {},
          crossAxisCount: 4,
        ),
      ),
    ));

    expect(find.text('完成'), findsNothing);

    // 长按第一格超过 500ms（Listener.onPointerDown 起计时器）。
    final TestGesture gesture = await tester.startGesture(const Offset(50, 50));
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.up();
    // 编辑态有 _Jiggle 无限循环动画，不能用 pumpAndSettle（永不 settle）。
    await tester.pump();

    expect(find.text('完成'), findsOneWidget, reason: '长按后应进入编辑态并显示完成按钮');

    // 点「完成」退出编辑态。
    await tester.tap(find.text('完成'));
    await tester.pump();
    expect(find.text('完成'), findsNothing, reason: '完成后应退出编辑态');
  });

  testWidgets('短按（<500ms）不进入编辑态', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SpanReorderableGrid<int>(
          items: const <int>[0, 1],
          spanOf: (int i) => const CardGridSpan(),
          keyOf: (int i) => 'k$i',
          itemBuilder: (BuildContext context, int index, int item) =>
              Container(key: ValueKey<int>(item), color: Colors.teal),
          onReorder: (_) {},
          crossAxisCount: 4,
        ),
      ),
    ));

    final TestGesture gesture = await tester.startGesture(const Offset(50, 50));
    await tester.pump(const Duration(milliseconds: 120));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('完成'), findsNothing, reason: '短按不应进入编辑态');
  });
}
