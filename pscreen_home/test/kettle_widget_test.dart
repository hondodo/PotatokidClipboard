import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pscreen_home/features/home/domain/models/kettle_summary.dart';
import 'package:pscreen_home/features/home/presentation/components/kettle_widget.dart';

KettleSummary _summary({required String status, required double temp}) =>
    KettleSummary(
      deviceId: 'dev_k',
      name: '米家智能电热水瓶 5L',
      status: status,
      temperature: temp,
      modes: const <String>['自来水', '纯净水', '凉白开'],
      mode: '自来水',
      targetTemperature: 100,
      keepWarmTemperature: 55,
      keepWarmOn: false,
      dechlorinationOn: false,
      rapidCoolingOn: false,
      childLocked: false,
      boilingPoint: 100,
      pureWaterKeepWarmTemperature: 66,
      tapWaterKeepWarmTemperature: 51,
      startEntityId: 'notify.k_start_cook_a_2_1',
      stopEntityId: 'button.k_cancel_cooking_a_2_2',
    );

void main() {
  testWidgets('热水瓶卡片保留 Spacer，底部文字/按钮按触屏放大',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 320,
          height: 188,
          child: KettleWidget(
            summary: _summary(status: '烧水中…', temp: 55),
            areaLabel: '客厅',
            showAreaInTitle: true,
          ),
        ),
      ),
    ));

    expect(find.byWidgetPredicate((w) => w is Spacer), findsOneWidget,
        reason: '保留旧版 Spacer 做上下分布');
    expect(find.text('客厅 米家智能电热水瓶 5L'), findsOneWidget);
    expect(find.text('客厅 · 烧水中… · 自来水'), findsOneWidget);
    expect(find.text('当前温度'), findsOneWidget);
    expect(find.text('目标 100°C'), findsOneWidget);
    expect(find.text('停止加热'), findsOneWidget);
    expect(find.byIcon(Icons.water_drop_rounded), findsOneWidget);

    // 按钮点击区 ≥ 42×92，字号 15，方便触屏点中。
    final ConstrainedBox box = tester.widget<ConstrainedBox>(find.ancestor(
          of: find.byType(OutlinedButton),
          matching: find.byType(ConstrainedBox),
        ).first);
    expect(box.constraints.minHeight, greaterThanOrEqualTo(42));
    expect(box.constraints.minWidth, greaterThanOrEqualTo(92));
    expect(tester.widget<Text>(find.text('停止加热')).style?.fontSize, 15);
  });

  testWidgets('热水瓶待机时按钮为「加热」，运行中点击走停止回调',
      (WidgetTester tester) async {
    int start = 0;
    int stop = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 320,
          height: 188,
          child: KettleWidget(
            summary: _summary(status: '待机中…', temp: 50),
            areaLabel: '客厅',
            onStart: () => start++,
            onStop: () => stop++,
          ),
        ),
      ),
    ));

    expect(find.text('加热'), findsOneWidget);
    await tester.tap(find.text('加热'));
    await tester.pump();
    expect(start, 1);
    expect(stop, 0);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 320,
          height: 188,
          child: KettleWidget(
            summary: _summary(status: '烧水中…', temp: 55),
            areaLabel: '客厅',
            onStart: () => start++,
            onStop: () => stop++,
          ),
        ),
      ),
    ));
    expect(find.text('停止加热'), findsOneWidget);
    await tester.tap(find.text('停止加热'));
    await tester.pump();
    expect(stop, 1);
    expect(start, 1);
  });
}
