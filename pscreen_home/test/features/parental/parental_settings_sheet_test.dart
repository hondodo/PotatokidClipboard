import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/features/parental/presentation/parental_realtime_settings_sheet.dart';
import 'package:pscreen_screen/core/network/realtime_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('家长设置弹层只展示遥控（实时通道）状态与网关', (WidgetTester tester) async {
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
    // 其它设置项一律不可见、不可操作。
    expect(find.text('屏保时间'), findsNothing);
    expect(find.text('界面缩放'), findsNothing);
    expect(find.text('屏保壁纸'), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });
}
