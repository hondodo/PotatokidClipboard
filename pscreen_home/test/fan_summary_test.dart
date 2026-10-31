import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/features/home/domain/models/fan_summary.dart';
import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';

HaEntityStateModel _e(
  String entityId,
  String state, {
  String? name,
  Map<String, dynamic> attributes = const <String, dynamic>{},
}) =>
    HaEntityStateModel(
      entityId: entityId,
      state: state,
      attributes: <String, dynamic>{
        'friendly_name': ?name,
        ...attributes,
      },
    );

List<HaEntityStateModel> _entities({
  String state = 'on',
  int percentage = 100,
  String mode = '直吹风',
  bool oscillating = false,
  String delay = '259',
}) =>
    <HaEntityStateModel>[
      _e(
        'fan.dmaker_cn_811545409_p8_s_2_fan',
        state,
        name: '随便改的名字 风扇',
        attributes: <String, dynamic>{
          'preset_modes': <String>['直吹风', '睡眠风'],
          'preset_mode': mode,
          'percentage': percentage,
          'percentage_step': 33.333333333333336,
          'oscillating': oscillating,
        },
      ),
      _e(
        'number.dmaker_cn_811545409_p8_off_delay_time_p_2_10',
        delay,
        name: '完全无关的延时名字',
      ),
    ];

void main() {
  group('FanSummary', () {
    test('按 fan 属性和 number 延时解析，不依赖名称', () {
      final FanSummary? summary = FanSummary.tryBuild(
        deviceId: 'dev_fan',
        name: '风扇',
        entities: _entities(),
      );

      expect(summary, isNotNull);
      expect(summary!.isOn, isTrue);
      expect(summary.modes, <String>['直吹风', '睡眠风']);
      expect(summary.mode, '直吹风');
      expect(summary.percentage, 100);
      expect(summary.speedLevel, 3);
      expect(summary.speedLabel, '三挡');
      expect(summary.oscillating, isFalse);
      expect(summary.delayMinutes, 259);
      expect(summary.delayLabel, '4小时19分钟');
      expect(
        summary.delayEntityId,
        'number.dmaker_cn_811545409_p8_off_delay_time_p_2_10',
      );
      expect(summary.statusLabel, '直吹风 · 三挡');
    });

    test('33% / 66% / 100% 对应一 / 二 / 三挡', () {
      expect(
        FanSummary.tryBuild(
          deviceId: 'd',
          name: 'f',
          entities: _entities(percentage: 33),
        )!
            .speedLevel,
        1,
      );
      expect(
        FanSummary.tryBuild(
          deviceId: 'd',
          name: 'f',
          entities: _entities(percentage: 66),
        )!
            .speedLevel,
        2,
      );
      expect(
        FanSummary.tryBuild(
          deviceId: 'd',
          name: 'f',
          entities: _entities(percentage: 100),
        )!
            .speedLevel,
        3,
      );
    });

    test('风扇灯：无级调速、无摆风、延时走 p_6_2', () {
      final FanSummary summary = FanSummary.tryBuild(
        deviceId: 'dev_cfan',
        name: '风扇灯',
        entities: <HaEntityStateModel>[
          _e(
            'fan.xiaomi_cn_991270332_cfan01_s_4_fan',
            'on',
            name: '随便改的名字',
            attributes: <String, dynamic>{
              'preset_modes': <String>['直吹风', '自然风', '循环风', '睡眠'],
              'preset_mode': '直吹风',
              'percentage': 100,
              'percentage_step': 1.0,
            },
          ),
          _e(
            'number.xiaomi_cn_991270332_cfan01_delay_time_p_6_2',
            '60',
            name: '延时',
            attributes: <String, dynamic>{'min': 0, 'max': 720},
          ),
          _e(
            'switch.xiaomi_cn_991270332_cfan01_all_on_p_10_1',
            'on',
            name: '总开关',
          ),
        ],
      )!;
      expect(summary.isContinuous, isTrue);
      expect(summary.speedLabel, '100');
      expect(summary.modes.length, 4);
      expect(summary.supportsOscillation, isFalse);
      expect(
        summary.delayEntityId,
        'number.xiaomi_cn_991270332_cfan01_delay_time_p_6_2',
      );
      expect(summary.delayMaxMinutes, 720);
      expect(summary.delayLabel, '1小时');
      expect(
        summary.masterSwitchEntityId,
        'switch.xiaomi_cn_991270332_cfan01_all_on_p_10_1',
      );
      expect(summary.masterOn, isTrue);
    });

    test('关闭状态与延时文案', () {
      final FanSummary summary = FanSummary.tryBuild(
        deviceId: 'd',
        name: 'f',
        entities: _entities(state: 'off', delay: '0'),
      )!;
      expect(summary.isOn, isFalse);
      expect(summary.statusLabel, '已关闭');
      expect(summary.delayLabel, '关闭');
    });

    test('没有 fan 实体时返回 null', () {
      final FanSummary? summary = FanSummary.tryBuild(
        deviceId: 'd',
        name: '普通开关',
        entities: <HaEntityStateModel>[
          _e('switch.other', 'off', name: '普通开关'),
        ],
      );
      expect(summary, isNull);
    });
  });
}
