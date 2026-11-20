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
      attributes: <String, dynamic>{
        'friendly_name': name.isEmpty ? id : name,
      },
    );

void main() {
  group('CardSpan 解析', () {
    test('默认 1×1，越界收敛到 1~4', () {
      expect(const CardSpan().col, 1);
      expect(const CardSpan().row, 1);
      final CardSpan big = CardSpan.fromJson(<String, dynamic>{'col': 2, 'row': 3});
      expect(big.col, 2);
      expect(big.row, 3);
      final CardSpan clamped = CardSpan.fromJson(<String, dynamic>{'col': 9, 'row': 0});
      expect(clamped.col, 4);
      expect(clamped.row, 1);
    });
  });

  group('CardLayoutNode 解析', () {
    test('递归解析 row/children 与 repeat/template', () {
      final CardLayoutNode node = CardLayoutNode.fromJson(<String, dynamic>{
        'type': 'column',
        'gap': 8,
        'children': <dynamic>[
          <String, dynamic>{
            'type': 'repeat',
            'source': 'gangs',
            'item': 'gang',
            'columns': 2,
            'template': <String, dynamic>{
              'type': 'button',
              'label': '{gang.label}',
              'style': '{gang.style}',
              'onClick': 'toggle@{gang.entityId}',
            },
          },
        ],
      });
      expect(node.type, 'column');
      expect(node.gap, 8);
      expect(node.children, hasLength(1));
      final CardLayoutNode repeat = node.children.first;
      expect(repeat.type, 'repeat');
      expect(repeat.item, 'gang');
      expect(repeat.columns, 2);
      expect(repeat.template?.label, '{gang.label}');
      expect(repeat.template?.style, '{gang.style}');
    });
  });

  group('CardEvalContext 占位符求值', () {
    final HaDeviceGroup switchGroup = HaDeviceGroup(
      deviceId: 'dev_sw',
      title: '小米双开',
      entities: <HaEntityStateModel>[
        _entity('switch.a_on_p_2_1', 'on', name: '左键'),
        _entity('switch.a_on_p_3_1', 'off', name: '右键'),
      ],
    );
    final DeviceCardConfig card = DeviceCardConfig(
      label: '已开启路数',
      mainFmt: '{v}',
      subTpl: '{state}',
    );

    test('基础占位符 title/gangCount/gangOnCount', () {
      final CardEvalContext ctx = CardEvalContext(group: switchGroup, card: card);
      expect(ctx.resolve('{title}'), '小米双开');
      expect(ctx.resolve('{gangCount}'), '2');
      expect(ctx.resolve('{gangOnCount}'), '1');
    });

    test('repeat 项占位符按 item 名解析', () {
      final CardEvalContext ctx = CardEvalContext(
        group: switchGroup,
        card: card,
        itemName: 'gang',
        itemValues: <String, String>{
          'label': '左键',
          'entityId': 'switch.a_on_p_2_1',
          'style': 'active',
          'stateLabel': '已开启 · 点击关闭',
        },
      );
      expect(ctx.resolve('{gang.label}'), '左键');
      expect(ctx.resolve('toggle@{gang.entityId}'), 'toggle@switch.a_on_p_2_1');
      expect(ctx.resolve('{gang.style}'), 'active');
      expect(ctx.resolve('{item.label}'), '左键');
    });

    test('visibleWhen 条件求值', () {
      final CardEvalContext withPrimary = CardEvalContext(group: switchGroup, card: card);
      expect(withPrimary.evalCondition('{primary.switchable}'), isTrue);
      expect(withPrimary.evalCondition("{gangOnCount} > '0'"), isTrue);
      expect(withPrimary.evalCondition("{gangOnCount} = '9'"), isFalse);
    });

    test('三元表达式求值', () {
      final CardEvalContext ctx = CardEvalContext(
        group: switchGroup,
        card: card,
        itemName: 'gang',
        itemValues: <String, String>{'isOn': 'true'},
      );
      expect(ctx.resolve("{gang.isOn ? '开' : '关'}"), '开');
    });
  });

  group('gangValues 路列表', () {
    test('按可开关实体生成，每路含 label/style/entityId', () {
      final HaDeviceGroup group = HaDeviceGroup(
        deviceId: 'dev_sw',
        title: '双开',
        entities: <HaEntityStateModel>[
          _entity('switch.a_on_p_2_1', 'on', name: '左键'),
          _entity('switch.a_on_p_3_1', 'off', name: '右键'),
          _entity('sensor.power', '65', name: '功率'), // 非开关，不计入
        ],
      );
      final List<Map<String, String>> gangs = gangValues(group);
      expect(gangs, hasLength(2));
      // HaDeviceGroup 会按 displayName 排序实体，故用 entityId 定位而非下标。
      final Map<String, String> left = gangs.firstWhere((Map<String, String> g) => g['entityId'] == 'switch.a_on_p_2_1');
      final Map<String, String> right = gangs.firstWhere((Map<String, String> g) => g['entityId'] == 'switch.a_on_p_3_1');
      expect(left['label'], '左键');
      expect(left['style'], 'active');
      expect(right['style'], 'normal');
    });
  });

  group('默认布局', () {
    test('multi_switch 用 repeat 大按钮，无「已开启路数」文字', () {
      const DeviceCardConfig card = DeviceCardConfig();
      final CardLayoutNode layout = CardLayoutBuilder.defaultLayout('multi_switch', card);
      expect(layout.type, 'column');
      expect(layout.children.map((CardLayoutNode n) => n.type), contains('repeat'));
      final CardLayoutNode repeat = layout.children.firstWhere((CardLayoutNode n) => n.type == 'repeat');
      expect(repeat.source, 'gangs');
      expect(repeat.template?.onClick, 'toggle@{gang.entityId}');
      // 默认布局里不应出现「已开启路数」统计文字节点。
      final String dump = layout.children
          .map((CardLayoutNode n) => n.value ?? '')
          .join('|');
      expect(dump.contains('已开启路数'), isFalse);
    });

    test('其它类型用通用布局（text+button+chip）', () {
      const DeviceCardConfig card = DeviceCardConfig(
        buttons: <DeviceCardButton>[DeviceCardButton(label: '开关', action: 'toggle')],
      );
      final CardLayoutNode layout = CardLayoutBuilder.defaultLayout('socket', card);
      expect(layout.type, 'column');
      expect(layout.children.length, 3); // header + main + wrap
    });
  });
}
