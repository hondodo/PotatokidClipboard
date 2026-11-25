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

    test('长 friendly_name 剥离设备名前缀，不出现超长文本', () {
      const String device = '小米米家智能开关（双开单控）';
      final HaDeviceGroup group = HaDeviceGroup(
        deviceId: 'dev_dhkg02',
        title: device,
        entities: <HaEntityStateModel>[
          _entity(
            'switch.dhkg02_on_p_2_1',
            'off',
            name: '$device 右键-$device-右键',
          ),
          _entity(
            'switch.dhkg02_on_p_3_1',
            'on',
            name: '$device 客厅灯 左键',
          ),
        ],
      );
      final List<Map<String, String>> gangs = gangValues(group);
      final Map<String, String> right = gangs.firstWhere((Map<String, String> g) => g['entityId'] == 'switch.dhkg02_on_p_2_1');
      final Map<String, String> left = gangs.firstWhere((Map<String, String> g) => g['entityId'] == 'switch.dhkg02_on_p_3_1');
      expect(right['label'], '右键');
      expect(left['label'], '客厅灯');
      // 绝不把完整实体名当按钮标签。
      for (final Map<String, String> g in gangs) {
        expect(g['label']!.contains(device), isFalse);
      }
    });
  });

  group('空调风速步进', () {
    const List<String> modes = <String>['自动', '一档', '二档', '三档', 'Max档'];

    test('± 按 fan_modes 索引步进，两端钳制不回绕', () {
      expect(climateFanStepTarget(modes, '自动', delta: -1), '自动');
      expect(climateFanStepTarget(modes, '二档', delta: -1), '一档');
      expect(climateFanStepTarget(modes, '二档', delta: 1), '三档');
      expect(climateFanStepTarget(modes, 'Max档', delta: 1), 'Max档');
    });

    test('不认识当前档位时从边界起步；空列表返回 null', () {
      expect(climateFanStepTarget(modes, '未知', delta: 1), '自动');
      expect(climateFanStepTarget(modes, '未知', delta: -1), '自动');
      expect(climateFanStepTarget(<String>[], '自动', delta: 1), isNull);
    });

    test('不带 delta 保持旧循环行为', () {
      expect(climateFanStepTarget(modes, 'Max档'), '自动');
      expect(climateFanStepTarget(modes, '二档'), '三档');
    });
  });

  group('数值阈值映射', () {
    test('applyRules 按出现顺序取首个命中，default 兜底', () {
      final Map<String, String> rules = CardEvalContext.parseValueMap(
        '>=30=高温,>=20=舒适,default=偏低',
      )!;
      expect(CardEvalContext.applyRules('32.5', rules), '高温');
      expect(CardEvalContext.applyRules('26', rules), '舒适');
      expect(CardEvalContext.applyRules('12', rules), '偏低');
      expect(CardEvalContext.applyRules('unknown', rules), '偏低');
      // default 写在最前面也一样兜底。
      final Map<String, String> reversed = CardEvalContext.parseValueMap(
        'default=偏低,>=20=舒适',
      )!;
      expect(CardEvalContext.applyRules('25', reversed), '舒适');
      expect(CardEvalContext.applyRules('5', reversed), '偏低');
    });

    test('支持 > <= < = != 与整值精确匹配', () {
      // 注意从上往下首个命中胜出：=0 要写在 <=20 前面才生效。
      final Map<String, String> rules = CardEvalContext.parseValueMap(
        '>1000=大功率,=0=零,<=20=低电量,!=0=有值,on=开启',
      )!;
      expect(CardEvalContext.applyRules('1500', rules), '大功率');
      expect(CardEvalContext.applyRules('15', rules), '低电量');
      expect(CardEvalContext.applyRules('0', rules), '零');
      expect(CardEvalContext.applyRules('55', rules), '有值');
      expect(CardEvalContext.applyRules('on', rules), '开启');
      expect(CardEvalContext.applyRules('off', rules), 'off');
    });

    test('无 default 且未命中时返回原值，applyRulesOrNull 能区分未命中', () {
      final Map<String, String> rules = CardEvalContext.parseValueMap('>=50=高')!;
      expect(CardEvalContext.applyRules('10', rules), '10');
      expect(CardEvalContext.applyRulesOrNull('10', rules), isNull);
      expect(CardEvalContext.applyRulesOrNull('80', rules), '高');
    });

    test('内联占位符规则同样支持阈值与 default', () {
      final HaDeviceGroup group = HaDeviceGroup(
        deviceId: 'dev.test',
        title: '客厅',
        entities: <HaEntityStateModel>[
          _entity('sensor.temp', '26.5', name: '温度'),
          _entity('sensor.hum', '42', name: '湿度'),
        ],
      );
      final CardEvalContext ctx = CardEvalContext(group: group, card: const DeviceCardConfig());
      expect(ctx.resolve('{s:temp|>=30=高温,>=20=舒适,default=偏低}'), '舒适');
      expect(ctx.resolve('{s:hum|>=50=潮,default=干}'), '干');
    });

    test('visibleWhen 支持数值比较', () {
      final HaDeviceGroup group = HaDeviceGroup(
        deviceId: 'dev.test',
        title: '客厅',
        entities: <HaEntityStateModel>[_entity('sensor.battery', '25', name: '电量')],
      );
      final CardEvalContext ctx = CardEvalContext(group: group, card: const DeviceCardConfig());
      expect(ctx.evalCondition('{s:battery}>=20'), isTrue);
      expect(ctx.evalCondition('{s:battery}>=30'), isFalse);
      expect(ctx.evalCondition('{s:battery}<30'), isTrue);
      expect(ctx.evalCondition('{s:battery}!=25'), isFalse);
    });
  });

  group('spacer / sizedBox 解析', () {
    test('flex 与 width/height 从 JSON 读出', () {
      final CardLayoutNode row = CardLayoutNode.fromJson(<String, dynamic>{
        'type': 'row',
        'children': <dynamic>[
          <String, dynamic>{'type': 'spacer', 'flex': 3},
          <String, dynamic>{'type': 'sizedBox', 'width': 12, 'height': 8},
        ],
      });
      expect(row.children[0].type, 'spacer');
      expect(row.children[0].flex, 3);
      expect(row.children[1].type, 'sizedBox');
      expect(row.children[1].width, 12);
      expect(row.children[1].height, 8);
    });

    test('bg / bgMap / bgRadius 从 JSON 读出', () {
      final CardLayoutNode node = CardLayoutNode.fromJson(<String, dynamic>{
        'type': 'column',
        'bg': '{attr.current_temperature}',
        'bgMap': '>=30=#FF5252,default=#4CAF50',
        'bgRadius': 16,
      });
      expect(node.bg, '{attr.current_temperature}');
      expect(node.bgMap, '>=30=#FF5252,default=#4CAF50');
      expect(node.bgRadius, 16);
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
