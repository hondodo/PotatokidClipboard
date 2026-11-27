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

  group('notify 动作解析', () {
    test('按第一个冒号拆分实体与 YAML 列表消息', () {
      final parsed = parseNotifyAction(
        'notify@notify.chunmi_cn_958338880_cmwy3_start_cook_a_2_1:[1]',
      );
      expect(parsed, isNotNull);
      expect(parsed!.entityId,
          'notify.chunmi_cn_958338880_cmwy3_start_cook_a_2_1');
      expect(parsed.message, '[1]');
    });

    test('消息含逗号/方括号完整保留（热水瓶 8 项参数）', () {
      final parsed = parseNotifyAction('notify@notify.kettle_start:[M0, 95, true, 55, false, false, 45, 40]');
      expect(parsed, isNotNull);
      expect(parsed!.message, '[M0, 95, true, 55, false, false, 45, 40]');
    });

    test('格式非法返回 null（无前缀 / 无冒号 / 空实体）', () {
      expect(parseNotifyAction('press@button.start'), isNull);
      expect(parseNotifyAction('notify@notify.start'), isNull);
      expect(parseNotifyAction('notify@:[1]'), isNull);
    });
  });

  group('draftOption / commitDraft 动作解析', () {
    test('draftOption 复用 selectOption 拆分，带选项直接暂存', () {
      final parsed = parseDraftOptionAction('draftOption@select.mode:鸡翅');
      expect(parsed, isNotNull);
      expect(parsed!.entityId, 'select.mode');
      expect(parsed.option, '鸡翅');
    });

    test('draftOption 不带选项表示弹层选择', () {
      final parsed = parseDraftOptionAction('draftOption@select.mode');
      expect(parsed, isNotNull);
      expect(parsed!.entityId, 'select.mode');
      expect(parsed.option, isNull);
    });

    test('draftOption 格式非法返回 null', () {
      expect(parseDraftOptionAction('selectOption@select.mode'), isNull);
      expect(parseDraftOptionAction('draftOption@'), isNull);
    });

    test('commitDraft 支持多个 select + 启动按钮', () {
      final parsed = parseCommitDraftAction(
        'commitDraft@select.mode:texture_p_2_32:target_cooking_measure_p_2_29:button.start',
      );
      expect(parsed, <String>[
        'select.mode',
        'texture_p_2_32',
        'target_cooking_measure_p_2_29',
        'button.start',
      ]);
    });

    test('commitDraft 单个实体也可解析', () {
      expect(parseCommitDraftAction('commitDraft@select.mode'), <String>['select.mode']);
    });

    test('commitDraft 格式非法返回 null', () {
      expect(parseCommitDraftAction('draftOption@select.mode'), isNull);
      expect(parseCommitDraftAction('commitDraft@:button.start'), isNull);
      expect(parseCommitDraftAction('commitDraft@select.mode:'), isNull);
      expect(parseCommitDraftAction('commitDraft@'), isNull);
    });
  });

  group('draftCycle 动作解析', () {
    test('draftCycle 默认下一项', () {
      final parsed = parseDraftCycleAction('draftCycle@select.mode');
      expect(parsed, isNotNull);
      expect(parsed!.entityId, 'select.mode');
      expect(parsed.delta, 1);
    });

    test('draftCycle 支持上一项/下一项', () {
      final next = parseDraftCycleAction('draftCycle@select.mode:+1');
      expect(next!.delta, 1);
      final prev = parseDraftCycleAction('draftCycle@select.mode:-1');
      expect(prev!.entityId, 'select.mode');
      expect(prev.delta, -1);
    });

    test('draftCycle 格式非法返回 null', () {
      expect(parseDraftCycleAction('draftOption@select.mode'), isNull);
      expect(parseDraftCycleAction('draftCycle@'), isNull);
      expect(parseDraftCycleAction('draftCycle@select.mode:0'), isNull);
      expect(parseDraftCycleAction('draftCycle@select.mode:abc'), isNull);
    });
  });

  group('摄像机跨型号字段匹配', () {
    test('fallback 取到备选实体值后，节点级 map 仍能映射成文案', () {
      final HaDeviceGroup group = HaDeviceGroup(
        deviceId: 'dev-cam-hlmax',
        title: 'CW500双摄版',
        entities: <HaEntityStateModel>[
          _entity('switch.isa_cn_1142592181_hlmax_hl_filllight_switch_p_6_16', 'off'),
        ],
      );
      final CardEvalContext ctx = CardEvalContext(group: group, card: const DeviceCardConfig());
      final Map<String, String>? map = CardEvalContext.parseValueMap('on=补光灯 开,off=补光灯 关,default=补光灯');
      final String raw = ctx.resolve('{s:_s_21_white_light|fallback=s:_hl_filllight_switch_p_6_16}', map);
      expect(raw, '补光灯 关');
    });

    test('4双摄版有首选字段时 fallback 不生效，map 映射首选值', () {
      final HaDeviceGroup group = HaDeviceGroup(
        deviceId: 'dev-cam-cw501d',
        title: '4双摄版',
        entities: <HaEntityStateModel>[
          _entity('light.isa_cn_1179402375_cw501d_s_21_white_light', 'on'),
        ],
      );
      final CardEvalContext ctx = CardEvalContext(group: group, card: const DeviceCardConfig());
      final Map<String, String>? map = CardEvalContext.parseValueMap('on=补光灯 开,off=补光灯 关,default=补光灯');
      expect(ctx.resolve('{s:_s_21_white_light|fallback=s:_hl_filllight_switch_p_6_16}', map), '补光灯 开');
    });

    test('动作 id 通过 fallback 命中真实存在的实体', () {
      final HaDeviceGroup group = HaDeviceGroup(
        deviceId: 'dev-cam-hlmax',
        title: 'CW500双摄版',
        entities: <HaEntityStateModel>[
          _entity('switch.isa_cn_1142592181_hlmax_hl_filllight_switch_p_6_16', 'off'),
        ],
      );
      final CardEvalContext ctx = CardEvalContext(group: group, card: const DeviceCardConfig());
      expect(ctx.resolve('toggle@{id:_s_21_white_light|fallback=id:_hl_filllight_switch_p_6_16}'),
          'toggle@switch.isa_cn_1142592181_hlmax_hl_filllight_switch_p_6_16');
    });
  });

  group('摄像机三型号实测', () {
    CardEvalContext ctxFor(List<HaEntityStateModel> es) => CardEvalContext(
          group: HaDeviceGroup(deviceId: 'cam', title: 'cam', entities: es),
          card: const DeviceCardConfig(),
        );
    final Map<String, String> lightMap = CardEvalContext.parseValueMap('on=补光灯 开,off=补光灯 关,default=补光灯')!;
    final Map<String, String> netMap = CardEvalContext.parseValueMap('LAN=有线,2 Point 4 GHz Wireless=2.4G Wi-Fi,5 GHz Wireless=5G Wi-Fi,blank=网络正常,default=网络正常')!;

    test('cw501d 4双摄版：首选字段全部命中', () {
      final c = ctxFor([
        _entity('switch.isa_cn_1179402375_cw501d_on_p_2_1', 'on'),
        _entity('sensor.isa_cn_1179402375_cw501d_status_p_4_1', '正常'),
        _entity('sensor.isa_cn_1179402375_cw501d_access_mode_p_29_5', '2 Point 4 GHz Wireless'),
        _entity('light.isa_cn_1179402375_cw501d_s_21_white_light', 'off'),
      ]);
      expect(c.resolve('{s:_on_p_2_1|on=运行中,off=已关闭,default=已关闭}'), '运行中');
      expect(c.resolve('{s:_access_mode_p_29_5}', netMap), '2.4G Wi-Fi');
      expect(c.resolve('{s:_s_21_white_light|fallback=s:_hl_filllight_switch_p_6_16}', lightMap), '补光灯 关');
      expect(c.resolve('toggle@{id:_s_21_white_light|fallback=id:_hl_filllight_switch_p_6_16}'), 'toggle@light.isa_cn_1179402375_cw501d_s_21_white_light');
    });

    test('cw500 单摄：网络与补光灯走 fallback', () {
      final c = ctxFor([
        _entity('switch.isa_cn_1145794652_cw500_on_p_2_1', 'on'),
        _entity('sensor.isa_cn_1145794652_cw500_status_p_4_1', '正常'),
        _entity('switch.isa_cn_1145794652_cw500_hl_filllight_switch_p_6_16', 'off'),
      ]);
      expect(c.resolve('{s:_access_mode_p_29_5}', netMap), '网络正常');
      expect(c.resolve('{s:_s_21_white_light|fallback=s:_hl_filllight_switch_p_6_16}', lightMap), '补光灯 关');
      expect(c.resolve('toggle@{id:_s_21_white_light|fallback=id:_hl_filllight_switch_p_6_16}'), 'toggle@switch.isa_cn_1145794652_cw500_hl_filllight_switch_p_6_16');
    });

    test('hlmax 双摄版：网络与补光灯走 fallback', () {
      final c = ctxFor([
        _entity('switch.isa_cn_1142592181_hlmax_on_p_2_1', 'on'),
        _entity('sensor.isa_cn_1142592181_hlmax_status_p_4_1', '正常'),
        _entity('switch.isa_cn_1142592181_hlmax_hl_filllight_switch_p_6_16', 'on'),
      ]);
      expect(c.resolve('{s:_access_mode_p_29_5}', netMap), '网络正常');
      expect(c.resolve('{s:_s_21_white_light|fallback=s:_hl_filllight_switch_p_6_16}', lightMap), '补光灯 开');
      expect(c.resolve('toggle@{id:_s_21_white_light|fallback=id:_hl_filllight_switch_p_6_16}'), 'toggle@switch.isa_cn_1142592181_hlmax_hl_filllight_switch_p_6_16');
    });
  });

  group('draft 占位符求值', () {
    test('{draft:后缀} 按 entity_id 子串匹配暂存值，按设备隔离', () {
      final HaDeviceGroup group = HaDeviceGroup(
        deviceId: 'dev-airfryer',
        title: '空气炸锅',
        entities: <HaEntityStateModel>[
          _entity('select.xiaomi_cn_877961796_maf16_mode_p_2_25', '手动模式'),
        ],
      );
      final CardEvalContext ctx = CardEvalContext(
        group: group,
        card: const DeviceCardConfig(),
        draftValues: <String, String>{
          'select.xiaomi_cn_877961796_maf16_mode_p_2_25': '鸡翅',
          'select.other_device_mode_p_2_25': '薯条',
        },
      );
      // 子串 mode_p_2_25 同时命中两个 key，取第一个遍历到的；这里用完整前缀消歧。
      expect(ctx.resolve('{draft:xiaomi_cn_877961796_maf16}'), '鸡翅');
      expect(ctx.resolve('{draft:other_device}'), '薯条');
      expect(ctx.resolve('{draft:not_exists}'), '');
    });

    test('无暂存时 draft 占位符返回空串', () {
      final HaDeviceGroup group = HaDeviceGroup(
        deviceId: 'dev-airfryer',
        title: '空气炸锅',
        entities: <HaEntityStateModel>[
          _entity('select.x_mode_p_2_25', '手动模式'),
        ],
      );
      final CardEvalContext ctx = CardEvalContext(group: group, card: const DeviceCardConfig());
      expect(ctx.resolve('{draft:mode_p_2_25}'), '');
    });

    test('fallback= 在无暂存时回退设备当前值，有暂存时优先暂存', () {
      final HaDeviceGroup group = HaDeviceGroup(
        deviceId: 'dev-airfryer',
        title: '空气炸锅',
        entities: <HaEntityStateModel>[
          _entity('select.x_mode_p_2_25', '手动模式'),
        ],
      );
      const DeviceCardConfig card = DeviceCardConfig();
      final String token = '{draft:mode_p_2_25|fallback=s:mode_p_2_25}';
      final CardEvalContext empty = CardEvalContext(group: group, card: card);
      expect(empty.resolve(token), '手动模式');
      final CardEvalContext staged = CardEvalContext(
        group: group,
        card: card,
        draftValues: <String, String>{'select.x_mode_p_2_25': '鸡翅'},
      );
      expect(staged.resolve(token), '鸡翅');
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

  group('diff 内联差值计算', () {
    test('diff= 计算当前值减去另一个占位符，可继续接阈值映射', () {
      final HaDeviceGroup group = HaDeviceGroup(
        deviceId: 'dev-fridge',
        title: '冰箱',
        entities: <HaEntityStateModel>[
          _entity('sensor.midjd_cn_temperature_p_3_1', '7'),
          _entity('number.midjd_cn_target_temperature_p_3_2', '5'),
        ],
      );
      final CardEvalContext ctx =
          CardEvalContext(group: group, card: const DeviceCardConfig());
      const String token =
          '{s:temperature_p_3_1|diff=s:target_temperature_p_3_2}';
      expect(ctx.resolve(token), '2');
      expect(
        ctx.resolve(
          '{s:temperature_p_3_1|diff=s:target_temperature_p_3_2,>0=偏高,default=正常}',
        ),
        '偏高',
      );
      expect(
        ctx.resolve(
          '{s:target_temperature_p_3_2|diff=s:temperature_p_3_1,<=0=偏低,>0=偏高}',
        ),
        '偏低',
      );
    });

    test('diff= 支持小数与负值，非数值回退原值', () {
      final HaDeviceGroup group = HaDeviceGroup(
        deviceId: 'dev-fridge',
        title: '冰箱',
        entities: <HaEntityStateModel>[
          _entity('sensor.x_temperature_p_4_1', '-17.5'),
          _entity('number.x_target_temperature_p_4_2', '-18'),
        ],
      );
      final CardEvalContext ctx =
          CardEvalContext(group: group, card: const DeviceCardConfig());
      expect(
        ctx.resolve('{s:temperature_p_4_1|diff=s:target_temperature_p_4_2}'),
        '0.5',
      );
      expect(ctx.resolve('{s:temperature_p_4_1|diff=s:not_exists}'), '-17.5');
    });
  });

  group('sec2min 秒转分钟', () {
    test('秒向上取整为分钟，0 保持 0', () {
      final HaDeviceGroup group = HaDeviceGroup(
        deviceId: 'dev-rice',
        title: '电饭煲',
        entities: <HaEntityStateModel>[
          _entity('sensor.cmwy3_left_time_p_3_3', '2700'),
        ],
      );
      final CardEvalContext ctx =
          CardEvalContext(group: group, card: const DeviceCardConfig());
      expect(ctx.resolve('{s:left_time_p_3_3}'), '2700');
      expect(ctx.resolve('{s:left_time_p_3_3|sec2min}'), '45');
    });

    test('不足 1 分钟按 1 分钟，0 秒仍为 0，非数值原样返回', () {
      final HaDeviceGroup group = HaDeviceGroup(
        deviceId: 'dev-rice',
        title: '电饭煲',
        entities: <HaEntityStateModel>[
          _entity('sensor.cmwy3_left_time_p_3_3', '30'),
        ],
      );
      final CardEvalContext ctx =
          CardEvalContext(group: group, card: const DeviceCardConfig());
      expect(ctx.resolve('{s:left_time_p_3_3|sec2min}'), '1');
      expect(ctx.resolve('{s:not_exists|sec2min}'), '');
      expect(
        ctx.resolve('{s:left_time_p_3_3|sec2min,>=1=烹饪中,default=待机}'),
        '烹饪中',
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

  group('休眠设备上次状态', () {
    final HaEntityStateModel sleeping = HaEntityStateModel(
      entityId: 'sensor.loock_t2pv1_door_state_p_3_1021',
      state: 'unavailable',
      attributes: const <String, dynamic>{'friendly_name': '门锁 门状态'},
      lastKnownState: '已上锁(反锁)',
      lastKnownAttributes: const <String, dynamic>{
        'friendly_name': '门锁 门状态',
      },
      lastKnownAt: DateTime(2026, 11, 27, 15, 58),
    );
    final HaDeviceGroup lockGroup = HaDeviceGroup(
      deviceId: 'dev_lock',
      title: '门锁',
      entities: <HaEntityStateModel>[sleeping],
    );
    const DeviceCardConfig card = DeviceCardConfig(label: '门锁', mainFmt: '{v}');

    test('last:<后缀> 取休眠前 state，当前值仍是 unavailable', () {
      final CardEvalContext ctx = CardEvalContext(group: lockGroup, card: card);
      expect(ctx.resolve('{s:door_state_p_3_1021}'), 'unavailable');
      expect(ctx.resolve('{last:door_state_p_3_1021}'), '已上锁(反锁)');
      expect(
        ctx.resolve(
          '{last:door_state_p_3_1021|已上锁(反锁)=已锁,default=未知}',
        ),
        '已锁',
      );
    });

    test('lastAt + ago 显示上次上报相对时间', () {
      final CardEvalContext ctx = CardEvalContext(group: lockGroup, card: card);
      final String out = ctx.resolve('{lastAt:door_state_p_3_1021|ago}');
      expect(out, isNot(''));
      expect(out, isNot('unavailable'));
    });

    test('last:<后缀>.<属性> 读上次属性值', () {
      final HaEntityStateModel battery = HaEntityStateModel(
        entityId: 'sensor.loock_t2pv1_battery_level_p_4_1003',
        state: 'unavailable',
        attributes: const <String, dynamic>{},
        lastKnownAttributes: const <String, dynamic>{
          'friendly_name': '门锁 电池电量',
        },
      );
      final CardEvalContext ctx = CardEvalContext(
        group: HaDeviceGroup(
          deviceId: 'dev_lock_battery',
          title: '门锁',
          entities: <HaEntityStateModel>[battery],
        ),
        card: card,
      );
      expect(ctx.resolve('{last:battery_level_p_4_1003.friendly_name}'), '门锁 电池电量');
    });

    test('blank=<文案> 只在空值时替换，有值原样保留', () {
      final CardEvalContext ctx = CardEvalContext(group: lockGroup, card: card);
      expect(ctx.resolve('{last:battery_level_p_4_1003|blank=—}'), '—');
      final HaEntityStateModel battery = HaEntityStateModel(
        entityId: 'sensor.loock_t2pv1_battery_level_p_4_1003',
        state: 'unavailable',
        attributes: const <String, dynamic>{},
        lastKnownState: '24',
      );
      final CardEvalContext ctx2 = CardEvalContext(
        group: HaDeviceGroup(
          deviceId: 'dev_lock_battery',
          title: '门锁',
          entities: <HaEntityStateModel>[battery],
        ),
        card: card,
      );
      expect(ctx2.resolve('{last:battery_level_p_4_1003|blank=—}'), '24');
      expect(
        ctx2.resolve('{last:battery_level_p_4_1003|<=20=#F87171,default=#7DD3FC}'),
        '#7DD3FC',
      );
    });

    test('没有 lastKnown 的设备保持空串，不误显示当前值', () {
      final HaEntityStateModel sleeping = HaEntityStateModel(
        entityId: 'sensor.loock_t2pv1_status_p_7_2',
        state: 'unavailable',
        attributes: const <String, dynamic>{},
      );
      final CardEvalContext ctx = CardEvalContext(
        group: HaDeviceGroup(
          deviceId: 'dev_lock_status',
          title: '门锁',
          entities: <HaEntityStateModel>[sleeping],
        ),
        card: card,
      );
      expect(ctx.resolve('{last:status_p_7_2}'), '');
    });

    test('快照 JSON 往返保留 lastKnown 字段', () {
      final Map<String, dynamic> json = sleeping.toJson();
      expect(json['lastKnownState'], '已上锁(反锁)');
      expect(json['lastKnownAttributes'], isA<Map<String, dynamic>>());
      expect(json['lastKnownAt'], isA<String>());
      final HaEntityStateModel restored = HaEntityStateModel.fromJson(json);
      expect(restored.lastKnownState, '已上锁(反锁)');
      expect(restored.lastKnownAt, isNotNull);
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

  group('休眠/离线三态判定', () {
    HaDeviceGroup groupOf(HaEntityStateModel e) => HaDeviceGroup(
          deviceId: 'd', title: '门锁', entities: <HaEntityStateModel>[e],
        );

    test('有可用实体恒为在线；未配宽限时休眠即离线', () {
      final HaDeviceGroup online = groupOf(_entity('sensor.lock_on', 'unavailable'));
      final CardEvalContext c1 = CardEvalContext(
        group: groupOf(_entity('sensor.a', 'on')),
        card: const DeviceCardConfig(sleepGraceSeconds: 3600),
      );
      expect(c1.presence, 'online');
      expect(c1.visualOn, isTrue);
      final CardEvalContext c2 = CardEvalContext(group: online, card: const DeviceCardConfig());
      expect(c2.presence, 'offline');
      expect(c2.visualOn, isFalse);
    });

    test('宽限期内休眠不灰、显示 {presence}=休眠；超时判离线并显示离线', () {
      final HaDeviceGroup fresh = groupOf(HaEntityStateModel(
        entityId: 'sensor.lock', state: 'unavailable',
        attributes: const <String, dynamic>{'friendly_name': '门锁'},
        lastKnownState: '已上锁',
        lastKnownAt: DateTime.now().subtract(const Duration(minutes: 5)),
      ));
      final CardEvalContext inGrace = CardEvalContext(
        group: fresh, card: const DeviceCardConfig(sleepGraceSeconds: 600),
      );
      expect(inGrace.presence, 'sleeping');
      expect(inGrace.visualOn, isTrue);
      expect(inGrace.resolve('{presence}'), '休眠');
      expect(inGrace.resolve('{presenceCode}'), 'sleeping');
      expect(inGrace.resolve('{last:lock|offline=离线}'), '已上锁');

      final HaDeviceGroup stale = groupOf(HaEntityStateModel(
        entityId: 'sensor.lock', state: 'unavailable',
        attributes: const <String, dynamic>{'friendly_name': '门锁'},
        lastKnownState: '已上锁',
        lastKnownAt: DateTime.now().subtract(const Duration(hours: 2)),
      ));
      final CardEvalContext expired = CardEvalContext(
        group: stale, card: const DeviceCardConfig(sleepGraceSeconds: 60),
      );
      expect(expired.presence, 'offline');
      expect(expired.visualOn, isFalse);
      expect(expired.resolve('{presence}'), '离线');
      // offline= 规则只在真离线时覆盖文案。
      expect(expired.resolve('{last:lock|offline=离线}'), '离线');
    });

    test('启动即休眠且从无上报：从首次观察起等满周期，不立刻判离线', () {
      final HaDeviceGroup neverReported = groupOf(HaEntityStateModel(
        entityId: 'sensor.lock', state: 'unavailable',
        attributes: const <String, dynamic>{'friendly_name': '门锁'},
        firstObservedAt: DateTime.now(),
      ));
      final CardEvalContext ctx = CardEvalContext(
        group: neverReported, card: const DeviceCardConfig(sleepGraceSeconds: 600),
      );
      expect(ctx.presence, 'sleeping', reason: '刚启动不能因无记录被当 0 立刻判离线');
      expect(ctx.visualOn, isTrue);

      final HaDeviceGroup longObserved = groupOf(HaEntityStateModel(
        entityId: 'sensor.lock', state: 'unavailable',
        attributes: const <String, dynamic>{'friendly_name': '门锁'},
        firstObservedAt: DateTime.now().subtract(const Duration(hours: 2)),
      ));
      expect(
        CardEvalContext(
          group: longObserved, card: const DeviceCardConfig(sleepGraceSeconds: 60),
        ).presence,
        'offline',
      );
    });

    test('firstObservedAt 随快照往返保留', () {
      final DateTime at = DateTime.now().subtract(const Duration(minutes: 3));
      final HaEntityStateModel e = HaEntityStateModel(
        entityId: 'sensor.lock', state: 'unavailable',
        attributes: const <String, dynamic>{}, firstObservedAt: at,
      );
      final HaEntityStateModel restored = HaEntityStateModel.fromJson(e.toJson());
      expect(restored.firstObservedAt, isNotNull);
      expect(restored.firstObservedAt!.difference(at).inSeconds.abs(), lessThan(2));
    });

    test('设备层 sleepGraceSeconds 从 JSON 读入并收敛到 0~30 天', () {
      expect(
        DeviceCardConfig.fromJson(<String, dynamic>{'sleepGraceSeconds': 86400})
            .sleepGraceSeconds,
        86400,
      );
      expect(
        DeviceCardConfig.fromJson(<String, dynamic>{'sleepGraceSeconds': 99999999})
            .sleepGraceSeconds,
        2592000,
      );
      expect(DeviceCardConfig.fromJson(<String, dynamic>{}).sleepGraceSeconds, 0);
    });
  });

  group('摄像机休眠友好占位符组合', () {
    // 第三台 CW500 双摄版休眠 9 小时：on/status 有 lastKnown，补光灯是 hl_filllight 型号。
    HaDeviceGroup sleepingCam() => HaDeviceGroup(
          deviceId: 'cam-cw500',
          title: '1楼 CW500双摄版',
          entities: <HaEntityStateModel>[
            HaEntityStateModel(
              entityId: 'switch.isa_cn_1145794652_cw500_on_p_2_1',
              state: 'unavailable',
              attributes: const <String, dynamic>{'friendly_name': '摄像机 电源'},
              lastKnownState: 'on',
              lastKnownAt: DateTime.now().subtract(const Duration(hours: 9)),
            ),
            HaEntityStateModel(
              entityId: 'sensor.isa_cn_1145794652_cw500_status_p_4_1',
              state: 'unavailable',
              attributes: const <String, dynamic>{'friendly_name': '摄像机 存储卡'},
              lastKnownState: '正常',
              lastKnownAt: DateTime.now().subtract(const Duration(hours: 9)),
            ),
            HaEntityStateModel(
              entityId: 'switch.isa_cn_1145794652_cw500_hl_filllight_switch_p_6_16',
              state: 'unavailable',
              attributes: const <String, dynamic>{'friendly_name': '摄像机 补光灯'},
              lastKnownState: 'off',
              lastKnownAt: DateTime.now().subtract(const Duration(hours: 9)),
            ),
          ],
        );

    test('休眠宽限期内：主状态/存储卡/补光灯显示上次值，不显示离线', () {
      final CardEvalContext ctx = CardEvalContext(
        group: sleepingCam(),
        // 9 小时前上报，宽限 24h → 休眠。
        card: const DeviceCardConfig(sleepGraceSeconds: 86400),
      );
      expect(ctx.presence, 'sleeping');
      expect(ctx.visualOn, isTrue);
      expect(
        ctx.resolve('{last:_on_p_2_1|offline=离线,on=运行中,off=已关闭,default=已关闭}'),
        '运行中',
      );
      expect(ctx.resolve('{last:_status_p_4_1|offline=离线,blank=未知}'), '正常');
      final Map<String, String> lightMap =
          CardEvalContext.parseValueMap('on=补光灯 开,off=补光灯 关,default=补光灯')!;
      expect(
        ctx.resolve(
          '{last:_s_21_white_light|fallback=last:_hl_filllight_switch_p_6_16}',
          lightMap,
        ),
        '补光灯 关',
      );
    });

    test('超时判离线：主状态与副行都显示离线文案', () {
      final CardEvalContext ctx = CardEvalContext(
        group: sleepingCam(),
        // 9 小时前上报，宽限 1h → 离线。
        card: const DeviceCardConfig(sleepGraceSeconds: 3600),
      );
      expect(ctx.presence, 'offline');
      expect(ctx.visualOn, isFalse);
      expect(
        ctx.resolve('{last:_on_p_2_1|offline=离线,on=运行中,off=已关闭,default=已关闭}'),
        '离线',
      );
      expect(ctx.resolve('{last:_status_p_4_1|offline=离线,blank=未知}'), '离线');
      expect(ctx.resolve('{presence}'), '离线');
    });

    test('动作 id 仍按真实实体解析（休眠也指向 hl_filllight）', () {
      final CardEvalContext ctx = CardEvalContext(
        group: sleepingCam(),
        card: const DeviceCardConfig(sleepGraceSeconds: 86400),
      );
      expect(
        ctx.resolve('toggle@{id:_s_21_white_light|fallback=id:_hl_filllight_switch_p_6_16}'),
        'toggle@switch.isa_cn_1145794652_cw500_hl_filllight_switch_p_6_16',
      );
    });
  });
}
