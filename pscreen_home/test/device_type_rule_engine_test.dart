import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/features/home/domain/models/device_type_dictionary.dart';

/// 规则引擎单测：验证与服务端 deviceTypes.js 一致的条件匹配 + 裁决逻辑。
void main() {
  Map<String, dynamic> entity({
    required String id,
    required String domain,
    required String name,
    String state = 'on',
    Map<String, dynamic> attrs = const <String, dynamic>{},
    Map<String, dynamic> device = const <String, dynamic>{},
  }) {
    return <String, dynamic>{
      'id': id,
      'domain': domain,
      'name': name,
      'state': state,
      'attrs': attrs,
      'device': device,
    };
  }

  DeviceTypeRule ruleOf({
    required String key,
    required int priority,
    required List<Map<String, dynamic>> rawRules,
  }) {
    return DeviceTypeRule.fromJson(<String, dynamic>{
      'key': key,
      'label': key,
      'priority': priority,
      'rules': rawRules,
    });
  }

  Map<String, dynamic> rawRule({
    required String name,
    required List<Map<String, dynamic>> conds,
  }) {
    return <String, dynamic>{
      'name': name,
      'enabled': true,
      'conds': conds,
    };
  }

  test('startsWith 忽略 button. 域前缀，按设备标识匹配', () {
    final DeviceRuleCondition c = DeviceRuleCondition.fromJson(<String, dynamic>{
      'field': 'entity_id',
      'op': 'startsWith',
      'value': 'xiaomi_cn_mitv_',
    });
    expect(
      c.matches(entity(
        id: 'button.xiaomi_cn_mitv_xxx_play_a_3_1',
        domain: 'button',
        name: '播放',
      )),
      isTrue,
    );
    expect(
      c.matches(entity(id: 'switch.other_device', domain: 'switch', name: '其他')),
      isFalse,
    );
  });

  test('device.model 等值匹配', () {
    final DeviceRuleCondition c = DeviceRuleCondition.fromJson(<String, dynamic>{
      'field': 'device.model',
      'op': 'eq',
      'value': 'xiaomi.tv.v1',
    });
    expect(
      c.matches(entity(
        id: 'button.tv_play',
        domain: 'button',
        name: '播放',
        device: <String, dynamic>{'model': 'xiaomi.tv.v1'},
      )),
      isTrue,
    );
  });

  test('attr.exists 与 contains 组合判定', () {
    final DeviceRuleCondition temp = DeviceRuleCondition.fromJson(<String, dynamic>{
      'field': 'attr.current_temperature',
      'op': 'exists',
      'value': '',
    });
    final DeviceRuleCondition opt = DeviceRuleCondition.fromJson(<String, dynamic>{
      'field': 'attr.options',
      'op': 'contains',
      'value': '自来水',
    });
    final Map<String, dynamic> kettle = entity(
      id: 'sensor.kettle_temperature_p_2_6',
      domain: 'sensor',
      name: '电热水瓶',
      attrs: <String, dynamic>{
        'current_temperature': 98,
        'options': <String>['自来水', '纯净水'],
      },
    );
    expect(temp.matches(kettle), isTrue);
    expect(opt.matches(kettle), isTrue);
  });

  test('具体度优先：插座(2 条件) 胜过 空调(1 条件)', () {
    final DeviceTypeDictionary dict = DeviceTypeDictionary(rules: <String, DeviceTypeRule>{
      'climate': ruleOf(
        key: 'climate',
        priority: 10,
        rawRules: <Map<String, dynamic>>[
          rawRule(name: '空调', conds: <Map<String, dynamic>>[
            <String, dynamic>{'field': 'domain', 'op': 'eq', 'value': 'climate'},
          ]),
        ],
      ),
      'socket': ruleOf(
        key: 'socket',
        priority: 20,
        rawRules: <Map<String, dynamic>>[
          rawRule(name: '空调插座', conds: <Map<String, dynamic>>[
            <String, dynamic>{'field': 'name', 'op': 'contains', 'value': '插座'},
            <String, dynamic>{'field': 'domain', 'op': 'eq', 'value': 'climate'},
          ]),
        ],
      ),
    });
    final List<Map<String, dynamic>> plug = <Map<String, dynamic>>[
      entity(
        id: 'climate.lumi_cn_649055521_mcn02',
        domain: 'climate',
        name: '空调插座',
        attrs: <String, dynamic>{'current_temperature': 29},
      ),
    ];
    expect(dict.classifyLocally(plug), 'socket');
  });

  test('fromApiJson 解析 rules/card/自动分类/灰度类型', () {
    final DeviceTypeDictionary dict = DeviceTypeDictionary.fromApiJson(<String, dynamic>{
      'types': <dynamic>[
        <String, dynamic>{
          'key': 'tv',
          'label': '电视',
          'icon': '▤',
          'color': '#2f9cff',
          'priority': 30,
          'rules': <dynamic>[
            <String, dynamic>{
              'id': 'r1',
              'name': '电视型号',
              'enabled': true,
              'conds': <dynamic>[
                <String, dynamic>{'field': 'device.model', 'op': 'startsWith', 'value': 'xiaomi.tv'},
              ],
            },
          ],
          'card': <String, dynamic>{
            'label': '播放状态',
            'genericEnabled': true,
            'buttons': <dynamic>[
              <String, dynamic>{'label': '播放', 'action': 'press'},
            ],
          },
        },
      ],
      'autoClassification': <String, dynamic>{'dev-1': 'tv'},
      'manualClassification': <String, dynamic>{},
      'genericCardTypes': <dynamic>['tv'],
    });
    expect(dict.classifiedTypeOf('dev-1'), 'tv');
    expect(dict.useGenericCard('tv'), isTrue);
    expect(dict.useGenericCard('climate'), isFalse);
    expect(dict.rule('tv')?.card?.genericEnabled, isTrue);
    expect(dict.rule('tv')?.card?.buttons.first.label, '播放');
  });
}
