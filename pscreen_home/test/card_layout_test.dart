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

  group('selectOption 动作解析', () {
    test('按第一个冒号拆分实体与选项', () {
      final parsed = parseSelectOptionAction(
        'selectOption@select.viomi_v12_fan_level_p_10_2:低风',
      );
      expect(parsed, isNotNull);
      expect(parsed!.entityId, 'select.viomi_v12_fan_level_p_10_2');
      expect(parsed.option, '低风');
    });

    test('选项本身含冒号时完整保留（如 23:00-06:00）', () {
      final parsed = parseSelectOptionAction(
        'selectOption@select.vm_enable_time:23:00-06:00',
      );
      expect(parsed, isNotNull);
      expect(parsed!.entityId, 'select.vm_enable_time');
      expect(parsed.option, '23:00-06:00');
    });

    test('不带选项（无冒号）表示循环下一项', () {
      final parsed = parseSelectOptionAction('selectOption@select.mode');
      expect(parsed, isNotNull);
      expect(parsed!.entityId, 'select.mode');
      expect(parsed.option, isNull);
    });

    test('格式非法返回 null（无前缀 / 空实体 / 空选项）', () {
      expect(parseSelectOptionAction('toggle@switch.light'), isNull);
      expect(parseSelectOptionAction('selectOption@'), isNull);
      expect(parseSelectOptionAction('selectOption@:低风'), isNull);
      expect(parseSelectOptionAction('selectOption@select.fan:'), isNull);
    });
  });

  group('fanOscillate / fanMode 动作解析', () {
    test('fanOscillate 不带参数表示取反', () {
      final parsed = parseFanOscillateAction('fanOscillate@fan.living');
      expect(parsed, isNotNull);
      expect(parsed!.entityId, 'fan.living');
      expect(parsed.oscillating, isNull);
    });

    test('fanOscillate 带 on/off 直接设定，含兼容写法', () {
      expect(parseFanOscillateAction('fanOscillate@fan.living:on')!.oscillating, true);
      expect(parseFanOscillateAction('fanOscillate@fan.living:off')!.oscillating, false);
      expect(parseFanOscillateAction('fanOscillate@fan.living:true')!.oscillating, true);
      expect(parseFanOscillateAction('fanOscillate@fan.living:0')!.oscillating, false);
      expect(parseFanOscillateAction('fanOscillate@fan.living:maybe'), isNull);
    });

    test('fanMode 不带 mode 表示循环下一个', () {
      final parsed = parseFanModeAction('fanMode@fan.living');
      expect(parsed, isNotNull);
      expect(parsed!.entityId, 'fan.living');
      expect(parsed.mode, isNull);
    });

    test('fanMode 带 mode 直接设定，含中文模式名', () {
      final parsed = parseFanModeAction('fanMode@fan.living:睡眠风');
      expect(parsed, isNotNull);
      expect(parsed!.mode, '睡眠风');
      expect(parseFanModeAction('fanMode@fan.living:'), isNull);
      expect(parseFanModeAction('toggle@fan.living'), isNull);
    });
  });

  group('waterHeaterTemp 动作解析', () {
    test('按最后一个冒号拆分实体与带符号增量', () {
      final plus = parseWaterHeaterTempAction(
        'waterHeaterTemp@water_heater.xiaomi_cn_m3_s_2_water_heater:+1',
      );
      expect(plus, isNotNull);
      expect(plus!.entityId, 'water_heater.xiaomi_cn_m3_s_2_water_heater');
      expect(plus.delta, 1);

      final minus = parseWaterHeaterTempAction(
        'waterHeaterTemp@water_heater.xiaomi_cn_m3_s_2_water_heater:-1',
      );
      expect(minus, isNotNull);
      expect(minus!.delta, -1);
    });

    test('支持小数增量（step 0.5 的设备）', () {
      final parsed = parseWaterHeaterTempAction(
        'waterHeaterTemp@water_heater.demo:-0.5',
      );
      expect(parsed, isNotNull);
      expect(parsed!.delta, -0.5);
    });

    test('格式非法返回 null（无前缀 / 无冒号 / 空实体 / 非数字 / 零增量）', () {
      expect(parseWaterHeaterTempAction('climateTemp@climate.ac:+1'), isNull);
      expect(parseWaterHeaterTempAction('waterHeaterTemp@water_heater.demo'), isNull);
      expect(parseWaterHeaterTempAction('waterHeaterTemp@:+1'), isNull);
      expect(parseWaterHeaterTempAction('waterHeaterTemp@water_heater.demo:abc'), isNull);
      expect(parseWaterHeaterTempAction('waterHeaterTemp@water_heater.demo:0'), isNull);
    });
  });

  group('number 动作解析与步进', () {
    test('按最后一个冒号拆分实体与带符号增量', () {
      final plus = parseNumberAction(
        'number@number.xiaomi_cn_maf16_target_temperature_p_2_7:+5',
      );
      expect(plus, isNotNull);
      expect(plus!.entityId, 'number.xiaomi_cn_maf16_target_temperature_p_2_7');
      expect(plus.delta, 5);

      final minus = parseNumberAction(
        'number@number.xiaomi_cn_maf16_target_time_p_2_5:-1',
      );
      expect(minus, isNotNull);
      expect(minus!.delta, -1);
    });

    test('格式非法返回 null（无前缀 / 无冒号 / 空实体 / 非数字 / 零增量）', () {
      expect(parseNumberAction('fan@fan.living:33'), isNull);
      expect(parseNumberAction('number@number.demo'), isNull);
      expect(parseNumberAction('number@:+5'), isNull);
      expect(parseNumberAction('number@number.demo:abc'), isNull);
      expect(parseNumberAction('number@number.demo:0'), isNull);
    });

    test('按 step 对齐并钳制在 min/max', () {
      // 温度 180 +5 → 185（step 5 对齐），上界 230 内。
      expect(
        numberStepTarget(current: 180, delta: 5, min: 40, max: 230, step: 5),
        185,
      );
      // 到上界后不再增加：228 +5 → clamp 230 → 对齐仍 230。
      expect(
        numberStepTarget(current: 228, delta: 5, min: 40, max: 230, step: 5),
        230,
      );
      // 时间 1 -1 → clamp 到 min 1。
      expect(
        numberStepTarget(current: 1, delta: -1, min: 1, max: 1440, step: 1),
        1,
      );
      // 未对齐的当前值按 step 就近对齐：43 +5=48 → 以 min 40 为基准对齐到 50。
      expect(
        numberStepTarget(current: 43, delta: 5, min: 40, max: 230, step: 5),
        50,
      );
    });

    test('字符串型 min/max/step 也能解析', () {
      expect(
        numberStepTarget(
          current: 10,
          delta: 5,
          min: '0',
          max: '100',
          step: '5',
        ),
        15,
      );
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

    test('|int 取整显示，去掉 number 实体 state 的 .0', () {
      final HaDeviceGroup group = HaDeviceGroup(
        deviceId: 'dev.fryer',
        title: '厨房',
        entities: <HaEntityStateModel>[
          _entity('number.target_temperature', '180.0', name: '设定温度'),
          _entity('sensor.mode', '手动模式', name: '模式'),
        ],
      );
      final CardEvalContext ctx = CardEvalContext(group: group, card: const DeviceCardConfig());
      expect(ctx.resolve('{s:target_temperature|int}'), '180');
      expect(ctx.resolve('{s:target_temperature|int}°C'), '180°C');
      // 非数值原样返回。
      expect(ctx.resolve('{s:mode|int}'), '手动模式');
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

    test('内联规则含 = 时先 resolve 再比较（多状态归组显隐）', () {
      final HaDeviceGroup group = HaDeviceGroup(
        deviceId: 'dev.fryer',
        title: '厨房',
        entities: <HaEntityStateModel>[
          _entity('sensor.fryer_status_p_2_2', '烹饪中', name: '工作状态'),
        ],
      );
      final CardEvalContext ctx = CardEvalContext(group: group, card: const DeviceCardConfig());
      // 规则内的 '=' 不应被当成比较符：烹饪中归为 show。
      expect(
        ctx.evalCondition(
          '{s:status_p_2_2|烹饪中=show,速烤中=show,待机中=hide,default=hide}=show',
        ),
        isTrue,
      );
      // 不在分组里的状态归为 hide。
      expect(
        ctx.evalCondition(
          '{s:status_p_2_2|暂停中=show,抽锅暂停=show,default=hide}=show',
        ),
        isFalse,
      );
      // 取反分组。
      expect(
        ctx.evalCondition(
          '{s:status_p_2_2|关机中=hide,待机中=hide,default=show}=show',
        ),
        isTrue,
      );
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
