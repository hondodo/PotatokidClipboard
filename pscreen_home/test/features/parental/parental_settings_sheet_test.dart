import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/features/parental/presentation/parental_realtime_settings_sheet.dart';
import 'package:pscreen_screen/core/network/realtime_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('家长设置弹层展示遥控状态与网关，并允许修改实时账号', (WidgetTester tester) async {
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
    // 实时账号 / 口令可编辑（保存后重连）。
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
