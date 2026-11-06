import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/features/parental/presentation/parental_realtime_settings_sheet.dart';
import 'package:pscreen_screen/app/config/app_config.dart';
import 'package:pscreen_screen/core/network/realtime_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('家长设置弹层展示遥控状态与网关，默认态仅允许修改名称', (WidgetTester tester) async {
    expect(AppConfig.enableChangeAccount, isFalse,
        reason: '默认关闭账号 / 口令编辑（`.env` 的 ENABLE_CHANGE_ACCOUNT=false）');

    final RealtimeChannel channel = RealtimeChannel(url: 'ws://127.0.0.1');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ParentalRealtimeSettingsSheet(channel: channel)),
      ),
    );
    await tester.pump();

    expect(find.text('遥控（实时通道）'), findsOneWidget);
    expect(find.textContaining('遥控通道：'), findsOneWidget);
    expect(find.textContaining('网关：ws://'), findsOneWidget);
    // 默认态：只提供展示名编辑，账号 / 口令入口隐藏。
    expect(find.widgetWithText(TextField, '更改名称'), findsOneWidget);
    expect(find.text('保存名称'), findsOneWidget);
    expect(find.widgetWithText(TextField, '实时账号'), findsNothing);
    expect(find.widgetWithText(TextField, '实时口令'), findsNothing);
    expect(find.text('保存并重连'), findsNothing);
    // 其它设置项一律不可见、不可操作。
    expect(find.text('屏保时间'), findsNothing);
    expect(find.text('界面缩放'), findsNothing);
    expect(find.text('屏保壁纸'), findsNothing);
  });

  testWidgets('调试开关打开时家长设置弹层仍可修改实时账号与口令', (WidgetTester tester) async {
    final bool previous = AppConfig.enableChangeAccount;
    AppConfig.enableChangeAccount = true;
    addTearDown(() {
      AppConfig.enableChangeAccount = previous;
    });

    final RealtimeChannel channel = RealtimeChannel(url: 'ws://127.0.0.1');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ParentalRealtimeSettingsSheet(channel: channel)),
      ),
    );
    await tester.pump();

    expect(find.text('遥控（实时通道）'), findsOneWidget);
    expect(find.widgetWithText(TextField, '更改名称'), findsOneWidget);
    expect(find.widgetWithText(TextField, '实时账号'), findsOneWidget);
    expect(find.widgetWithText(TextField, '实时口令'), findsOneWidget);
    expect(find.text('保存并重连'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, '实时账号'),
      'home94755b3b2fc1b1ee',
    );
    expect(find.text('home94755b3b2fc1b1ee'), findsOneWidget);
    // 其它设置项一律不可见、不可操作。
    expect(find.text('屏保时间'), findsNothing);
    expect(find.text('界面缩放'), findsNothing);
    expect(find.text('屏保壁纸'), findsNothing);
  });
}
