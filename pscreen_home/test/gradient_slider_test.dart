import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/features/home/presentation/components/gradient_slider.dart';

void main() {
  testWidgets('异步提交失败时滑条回滚到设备权威值', (WidgetTester tester) async {
    final Completer<bool> result = Completer<bool>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 200,
              child: GradientSlider(
                value: 68,
                colors: const <Color>[Colors.green, Colors.teal],
                onChangeEndAsync: (double _) => result.future,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final Rect slider = tester.getRect(find.byType(GradientSlider));
    // 拇指是唯一带 boxShadow 的 Container，用它的位置代表滑条当前值。
    final Finder thumb = find.byWidgetPredicate(
      (Widget w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration! as BoxDecoration).boxShadow != null,
    );
    final double before = tester.getRect(thumb).left;

    final Offset start = Offset(
      slider.left + slider.width * 0.68,
      slider.center.dy,
    );
    final Offset end = Offset(
      slider.left + slider.width * 0.9,
      slider.center.dy,
    );
    await tester.dragFrom(start, end - start);
    await tester.pump();
    expect(tester.getRect(thumb).left, greaterThan(before + 20));

    // 指令未下发成功（例如断线重连中被 bloc 拦截）：本地预览必须回退。
    result.complete(false);
    await tester.pumpAndSettle();
    expect(tester.getRect(thumb).left, closeTo(before, 1));
  });

}
