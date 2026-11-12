import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/features/remote_control/presentation/widgets/channel_number_pad.dart';
import 'package:pscreen_screen/features/msg/protocol/envelope_builder.dart';

String _display(WidgetTester tester) =>
    (tester.widget(find.byKey(const Key('channel-number-display'))) as Text).data!;

String _hint(WidgetTester tester) =>
    (tester.widget(find.byKey(const Key('channel-number-hint'))) as Text).data!;

void main() {
  testWidgets('3×4 键位齐全：1-9 + 0 + 立即跳台（占两格），无「清除」', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ChannelNumberPad(onCommand: (_) {}, enabled: true),
      ),
    ));

    for (final String d in <String>['1', '2', '3', '4', '5', '6', '7', '8', '9', '0']) {
      expect(find.text(d), findsOneWidget, reason: '数字键 $d 应存在');
    }
    expect(find.text('立即跳台'), findsOneWidget);
    expect(find.text('清除'), findsNothing, reason: '按需求去掉「清除」键');
    expect(find.text('输入频道号'), findsOneWidget, reason: '回显初始占位');
    expect(
      find.byKey(const Key('channel-number-hint')),
      findsOneWidget,
      reason: '提示走键盘内小字',
    );
  });

  testWidgets('逐位点击：本地回显累积 + 每位发一条 channel_digit', (
    WidgetTester tester,
  ) async {
    final List<String> commands = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ChannelNumberPad(onCommand: commands.add, enabled: true),
      ),
    ));

    // 016 频道的正确按法是 0→1→6（前导 0 + 1 + 6，电视端解析为 16）
    await tester.tap(find.byKey(const Key('digit-0')));
    await tester.tap(find.byKey(const Key('digit-1')));
    await tester.tap(find.byKey(const Key('digit-6')));
    await tester.pump();

    expect(commands, hasLength(3));
    for (int i = 0; i < 3; i++) {
      final Map<String, dynamic> env =
          jsonDecode(commands[i]) as Map<String, dynamic>;
      expect(env['t'], 'cmd');
      expect(env['name'], 'channel_digit');
    }
    expect(
      (jsonDecode(commands[0])['args'] as Map<String, dynamic>)['digit'],
      0,
    );
    expect(
      (jsonDecode(commands[2])['args'] as Map<String, dynamic>)['digit'],
      6,
    );
    expect(_display(tester), '016');
    await tester.tap(find.byKey(const Key('digit-9')));
    await tester.pump();
    expect(commands, hasLength(3), reason: '满 3 位后不再追加');
  });

  testWidgets('满 3 位后 2 秒自动清空本地回显，之后可继续输入（真机 121 卡死回归）', (
    WidgetTester tester,
  ) async {
    final List<String> commands = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ChannelNumberPad(onCommand: commands.add, enabled: true),
      ),
    ));

    for (final String key in <String>['digit-1', 'digit-2', 'digit-1']) {
      await tester.tap(find.byKey(Key(key)));
      await tester.pump();
    }
    expect(_display(tester), '121');
    expect(commands, hasLength(3));

    // 满 3 位再按被拒（电视端也按最多 3 位结算）
    await tester.tap(find.byKey(const Key('digit-9')));
    await tester.pump();
    expect(commands, hasLength(3), reason: '满 3 位后再按不发命令');

    // 停 2 秒：电视端已自行结算跳台，手机端只清本地回显（纯 UI，不下发命令）
    await tester.pump(const Duration(seconds: 2));
    expect(_display(tester), '输入频道号', reason: '2 秒后回显自动清空');
    expect(commands, hasLength(3), reason: '清回显不发任何跳台命令，结算权在电视端');

    // 清空后可继续输入，不再被 length>=3 拒绝
    await tester.tap(find.byKey(const Key('digit-5')));
    await tester.pump();
    expect(commands, hasLength(4));
    expect(_display(tester), '5');
  });

  testWidgets('立即跳台：有输入发 resolve 并清回显；空输入只内联提示不发命令', (
    WidgetTester tester,
  ) async {
    final List<String> commands = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ChannelNumberPad(onCommand: commands.add, enabled: true),
      ),
    ));

    // 空缓冲点立即跳台：不发命令，内联提示先输号
    await tester.tap(find.text('立即跳台'));
    await tester.pump();
    expect(commands, isEmpty);
    expect(_hint(tester), '请先输入频道号');

    // 输入后点立即跳台：发 channel_digit_resolve 并清空回显
    await tester.tap(find.byKey(const Key('digit-1')));
    await tester.tap(find.byKey(const Key('digit-6')));
    await tester.tap(find.text('立即跳台'));
    await tester.pump();
    expect(commands.last, buildCommandEnvelope('channel_digit_resolve'));
    expect(_display(tester), '输入频道号', reason: '结算后回显已清');
  });

  testWidgets('数字键提示走键盘内小字，不弹 SnackBar 抢焦点', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ChannelNumberPad(onCommand: (_) {}, enabled: true),
      ),
    ));

    await tester.tap(find.byKey(const Key('digit-1')));
    await tester.pump();
    expect(_hint(tester), contains('已发 1'));
    expect(find.byType(SnackBar), findsNothing, reason: '连续按数字不应弹黑条');
  });

  testWidgets('离线时所有键禁用', (WidgetTester tester) async {
    final List<String> commands = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ChannelNumberPad(onCommand: commands.add, enabled: false),
      ),
    ));
    await tester.tap(find.byKey(const Key('digit-5')));
    await tester.tap(find.text('立即跳台'));
    await tester.pump();
    expect(commands, isEmpty);
  });
}
