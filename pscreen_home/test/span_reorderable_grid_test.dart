import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pscreen_home/features/home/presentation/components/span_reorderable_grid.dart';

Widget _buildGrid({required ValueChanged<List<int>> onReorder}) {
  return MaterialApp(
    home: Scaffold(
      body: SpanReorderableGrid<int>(
        items: const <int>[0, 1, 2, 3],
        spanOf: (int i) => const CardGridSpan(),
        keyOf: (int i) => 'k$i',
        itemBuilder: (BuildContext context, int index, int item) =>
            Container(key: ValueKey<int>(item), color: Colors.teal),
        onReorder: onReorder,
        crossAxisCount: 4,
      ),
    ),
  );
}

void main() {
  testWidgets('长按空白处 500ms 进入编辑态并显示完成按钮，点完成退出', (WidgetTester tester) async {
    await tester.pumpWidget(_buildGrid(onReorder: (_) {}));

    expect(find.text('完成'), findsNothing);

    // 第一格占据 y=16..204，x≈50 是卡片；下方 y=300 是空白区。
    final TestGesture gesture = await tester.startGesture(const Offset(400, 300));
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.up();
    // 编辑态有 _Jiggle 无限循环动画，不能用 pumpAndSettle（永不 settle）。
    await tester.pump();

    expect(find.text('完成'), findsOneWidget, reason: '长按空白处应进入编辑态');

    await tester.tap(find.text('完成'));
    await tester.pump();
    expect(find.text('完成'), findsNothing, reason: '完成后应退出编辑态');
  });

  testWidgets('卡片上长按不进入编辑态，不影响卡片本身的操作', (WidgetTester tester) async {
    await tester.pumpWidget(_buildGrid(onReorder: (_) {}));

    final TestGesture gesture = await tester.startGesture(const Offset(50, 50));
    await tester.pump(const Duration(milliseconds: 800));
    await gesture.up();
    await tester.pump();

    expect(find.text('完成'), findsNothing, reason: '卡片长按时不能被排序抢占');
  });

  testWidgets('在卡片上拖动（滚动手势）不进入编辑态', (WidgetTester tester) async {
    await tester.pumpWidget(_buildGrid(onReorder: (_) {}));

    final TestGesture gesture = await tester.startGesture(const Offset(120, 150));
    await gesture.moveTo(const Offset(120, 100));
    await tester.pump(const Duration(milliseconds: 120));
    await gesture.moveTo(const Offset(120, 40));
    await tester.pump(const Duration(milliseconds: 120));
    await gesture.up();
    await tester.pump();

    expect(find.text('完成'), findsNothing, reason: '从卡片上开始的滚动不应触发排序');
  });

  testWidgets('短按空白处（<500ms）不进入编辑态', (WidgetTester tester) async {
    await tester.pumpWidget(_buildGrid(onReorder: (_) {}));

    final TestGesture gesture = await tester.startGesture(const Offset(400, 300));
    await tester.pump(const Duration(milliseconds: 120));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('完成'), findsNothing, reason: '短按不应进入编辑态');
  });
}
