import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/features/remote_control/presentation/widgets/channel_number_pad.dart';
import 'package:pscreen_screen/features/msg/protocol/envelope_builder.dart';

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
    // 回显初始占位
    expect(find.text('输入频道号'), findsOneWidget);
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
    // 本地回显 016，且不超过 3 位
    expect(find.byKey(const Key('channel-number-display')), findsOneWidget);
    expect(
      (tester.widget(find.byKey(const Key('channel-number-display'))) as Text).data,
      '016',
    );
    await tester.tap(find.byKey(const Key('digit-9')));
    await tester.pump();
    expect(commands, hasLength(3), reason: '满 3 位后不再追加');
  });

  testWidgets('立即跳台：有输入发 resolve 并清回显；空输入只提示不发命令', (
    WidgetTester tester,
  ) async {
    final List<String> commands = <String>[];
    final List<String> hints = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ChannelNumberPad(
          onCommand: commands.add,
          enabled: true,
          onHint: (String m, {bool error = false}) => hints.add(m),
        ),
      ),
    ));

    // 空缓冲点立即跳台：不发命令，提示先输号
    await tester.tap(find.text('立即跳台'));
    await tester.pump();
    expect(commands, isEmpty);
    expect(hints, contains('请先输入频道号'));

    // 输入后点立即跳台：发 channel_digit_resolve 并清空回显
    await tester.tap(find.byKey(const Key('digit-1')));
    await tester.tap(find.byKey(const Key('digit-6')));
    await tester.tap(find.text('立即跳台'));
    await tester.pump();
    expect(
      commands.last,
      buildCommandEnvelope('channel_digit_resolve'),
    );
    expect(
      (tester.widget(find.byKey(const Key('channel-number-display'))) as Text).data,
      '输入频道号',
      reason: '结算后回显已清',
    );
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
