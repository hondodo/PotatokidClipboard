import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pscreen_home/features/home/domain/models/card_layout.dart';
import 'package:pscreen_home/features/home/domain/models/device_type_dictionary.dart';
import 'package:pscreen_home/features/home/domain/models/ha_device_group.dart';
import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';
import 'package:pscreen_home/features/home/presentation/components/json_card_renderer.dart';
import 'package:pscreen_home/features/home/presentation/components/marquee_text.dart';

const String _long = '这是一段非常非常长的设备名称需要在卡片里完整显示出来';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: SizedBox(width: 100, height: 40, child: child)));

void main() {
  testWidgets('文字不超宽时跑马灯退化为普通文本，显示全文', (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(const MarqueeText(text: '短', style: TextStyle(fontSize: 14))));
    await tester.pump();
    expect(find.text('短'), findsOneWidget);
    expect(find.byType(ClipRect), findsNothing);
  });

  testWidgets('loop 模式用两份副本做无缝循环', (WidgetTester tester) async {
    await tester.pumpWidget(
      _wrap(MarqueeText(text: _long, style: const TextStyle(fontSize: 14), mode: MarqueeMode.loop)),
    );
    await tester.pump();
    expect(find.text(_long), findsNWidgets(2));
    expect(find.byType(ClipRect), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pingpong 模式只有一份文字，靠位移往返', (WidgetTester tester) async {
    await tester.pumpWidget(
      _wrap(
        MarqueeText(
          text: _long,
          style: const TextStyle(fontSize: 14),
          mode: MarqueeMode.pingpong,
          direction: MarqueeDirection.right,
          pause: 3,
        ),
      ),
    );
    await tester.pump();
    expect(find.text(_long), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('JSON 跑马灯字段解析并驱动渲染器', (WidgetTester tester) async {
    final Map<String, dynamic> json = <String, dynamic>{
      'type': 'text',
      'value': _long,
      'marquee': true,
      'marqueeMode': 'pingpong',
      'marqueeDirection': 'right',
      'marqueePause': 3,
      'marqueeSpeed': 60,
    };
    final CardLayoutNode node = CardLayoutNode.fromJson(json);
    expect(node.marquee, isTrue);
    expect(node.marqueeMode, 'pingpong');
    expect(node.marqueeDirection, 'right');
    expect(node.marqueePause, 3);
    expect(node.marqueeSpeed, 60);

    final HaDeviceGroup group = HaDeviceGroup(
      deviceId: 'dev_x',
      title: '测试设备',
      entities: <HaEntityStateModel>[
        HaEntityStateModel(entityId: 'switch.x_on', state: 'on', attributes: const <String, dynamic>{}),
      ],
    );
    final DeviceCardConfig card = DeviceCardConfig(
      label: '开关',
      color: '#4dd4ac',
      layout: node,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            height: 120,
            child: JsonCardRenderer(
              group: group,
              card: card,
              typeKey: 'switch',
              onOpenDetail: () {},
              onAction: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final MarqueeText marquee = tester.widget<MarqueeText>(find.byType(MarqueeText));
    expect(marquee.mode, MarqueeMode.pingpong);
    expect(marquee.direction, MarqueeDirection.right);
    expect(marquee.pause, 3);
    expect(marquee.speed, 60);
  });

  testWidgets('marquee=false 时仍是原来的省略号文本', (WidgetTester tester) async {
    final DeviceCardConfig card = DeviceCardConfig(
      label: '开关',
      color: '#4dd4ac',
      layout: CardLayoutNode.fromJson(<String, dynamic>{
        'type': 'text',
        'value': _long,
        'marquee': false,
      }),
    );
    final HaDeviceGroup group = HaDeviceGroup(
      deviceId: 'dev_y',
      title: '测试设备',
      entities: <HaEntityStateModel>[
        HaEntityStateModel(entityId: 'switch.y_on', state: 'off', attributes: const <String, dynamic>{}),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            height: 120,
            child: JsonCardRenderer(
              group: group,
              card: card,
              typeKey: 'switch',
              onOpenDetail: () {},
              onAction: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(MarqueeText), findsNothing);
    expect(tester.widget<Text>(find.text(_long)).overflow, TextOverflow.ellipsis);
  });
}
