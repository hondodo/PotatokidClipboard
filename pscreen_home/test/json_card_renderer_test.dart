import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pscreen_home/features/home/domain/models/card_layout.dart';
import 'package:pscreen_home/features/home/domain/models/device_type_dictionary.dart';
import 'package:pscreen_home/features/home/domain/models/ha_device_group.dart';
import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';
import 'package:pscreen_home/features/home/presentation/components/json_card_renderer.dart';

HaEntityStateModel _entity(String id, String state, {String name = ''}) =>
    HaEntityStateModel(
      entityId: id,
      state: state,
      attributes: <String, dynamic>{'friendly_name': name.isEmpty ? id : name},
    );

void main() {
  testWidgets('JsonCardRenderer 渲染通用默认布局不抛异常', (WidgetTester tester) async {
    final HaDeviceGroup group = HaDeviceGroup(
      deviceId: 'dev_socket',
      title: '客厅插座',
      entities: <HaEntityStateModel>[
        _entity('switch.socket_on', 'on', name: '插座'),
        _entity('sensor.power', '65', name: '功率'),
      ],
    );
    const DeviceCardConfig card = DeviceCardConfig(
      label: '开关状态', mainFmt: '{v}', subTpl: '{state}',
      icon: '⏻', color: '#4dd4ac',
      buttons: <DeviceCardButton>[DeviceCardButton(label: '开关', action: 'toggle')],
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 300,
          height: 188,
          child: JsonCardRenderer(
            group: group,
            card: card,
            typeKey: 'socket',
            onOpenDetail: () {},
            onAction: (_) {},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    // 渲染成功 = 没抛异常；验证标题出现。
    expect(find.textContaining('客厅插座'), findsWidgets);
  });

  testWidgets('JsonCardRenderer 渲染 multi_switch 每路大按钮不抛异常', (WidgetTester tester) async {
    final HaDeviceGroup group = HaDeviceGroup(
      deviceId: 'dev_sw',
      title: '小米双开',
      entities: <HaEntityStateModel>[
        _entity('switch.a_on_p_2_1', 'on', name: '左键'),
        _entity('switch.a_on_p_3_1', 'off', name: '右键'),
      ],
    );
    const DeviceCardConfig card = DeviceCardConfig(
      label: '已开启路数', mainFmt: '{v}', subTpl: '{state}',
      icon: '▦', color: '#a3a3a3',
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 260,
          child: JsonCardRenderer(
            group: group,
            card: card,
            typeKey: 'multi_switch',
            onOpenDetail: () {},
            onAction: (_) {},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    // 每路一个大按钮：label 显示的应该是实体名（左键/右键），不是"已开启路数 2/4"。
    expect(find.textContaining('左键'), findsWidgets);
    expect(find.textContaining('右键'), findsWidgets);
  });

  testWidgets('JsonCardRenderer 渲染服务端自定义 layout(含sparkline)不抛异常', (WidgetTester tester) async {
    final HaDeviceGroup group = HaDeviceGroup(
      deviceId: 'dev_socket',
      title: '客厅插座',
      entities: <HaEntityStateModel>[_entity('switch.socket_on', 'on', name: '插座')],
    );
    final CardLayoutNode layout = CardLayoutNode.fromJson(<String, dynamic>{
      'type': 'column',
      'gap': 8,
      'children': <dynamic>[
        <String, dynamic>{'type': 'text', 'value': '{title}', 'size': 14},
        <String, dynamic>{'type': 'text', 'value': '{main}', 'size': 24, 'color': '{color}'},
        <String, dynamic>{
          'type': 'sparkline', 'metric': 'power', 'height': 60, 'showLabels': true,
        },
      ],
    });
    final DeviceCardConfig card = DeviceCardConfig(
      label: '功率', mainFmt: '{v}W', subTpl: '{state}', color: '#4dd4ac', layout: layout,
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 260,
          child: JsonCardRenderer(
            group: group,
            card: card,
            typeKey: 'socket',
            onOpenDetail: () {},
            onAction: (_) {},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('客厅插座'), findsWidgets);
  });
}
