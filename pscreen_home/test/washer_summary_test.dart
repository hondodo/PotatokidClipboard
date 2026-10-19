import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';
import 'package:pscreen_home/features/home/domain/models/washer_summary.dart';

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

List<HaEntityStateModel> _washerEntities({
  String status = '已关机',
  String runStatus = '未运行',
  String leftTime = '0',
  String fault = 'No Faults',
}) =>
    <HaEntityStateModel>[
      _e('sensor.wm_status_p_2_2', status, name: '洗衣机 工作状态'),
      _e('sensor.wm_run_status_p_2_11', runStatus, name: '洗衣机 运行状态'),
      _e('sensor.wm_left_time_p_2_10', leftTime, name: '洗衣机 剩余时间'),
      _e('number.wm_reservation_left', '30', name: '洗衣机 预约剩余时间'),
      _e('sensor.wm_door_state_p_2_9', '舱门已开', name: '洗衣机 门状态'),
      _e('sensor.wm_fault_p_2_4', fault, name: '洗衣机 故障'),
      _e('sensor.wm_power_consumption_p_2_39', '14', name: '洗衣机 耗电量'),
      _e('sensor.wm_water_consumption_p_2_40', '521', name: '洗衣机 耗水量'),
      _e('sensor.wm_has_washed_times_p_2_13', '85', name: '洗衣机 已洗涤次数'),
      _e(
        'select.wm_mode_p_2_3',
        '智能洗',
        name: '洗衣机 模式',
        attributes: <String, dynamic>{
          'options': <String>['智能洗', '快速洗', '单烘干', '筒清洁'],
        },
      ),
      _e('switch.wm_alarm', 'on', name: '洗衣机 提示音 提示音'),
      _e('switch.wm_on_p_2_1', 'off', name: '洗衣机 洗衣机 开关'),
      _e('button.wm_start_wash_a_2_2', 'unknown', name: '洗衣机 开始洗涤'),
      _e('button.wm_pause_a_2_3', 'unknown', name: '洗衣机 暂停'),
      _e('button.wm_stop_washing_a_2_1', 'unknown', name: '洗衣机 停止洗涤'),
    ];

void main() {
  group('WasherSummary', () {
    test('从设备实体中解析状态 / 模式 / 电源 / 统计', () {
      final WasherSummary? summary = WasherSummary.tryBuild(
        deviceId: 'dev_wm',
        name: '米家洗衣机 洗烘12kg',
        entities: _washerEntities(),
      );

      expect(summary, isNotNull);
      expect(summary!.status, '已关机');
      expect(summary.isOn, isFalse);
      expect(summary.powerEntityId, 'switch.wm_on_p_2_1',
          reason: '主电源必须是开关，而不是提示音');
      expect(summary.modeEntityId, 'select.wm_mode_p_2_3');
      expect(summary.mode, '智能洗');
      expect(summary.modes, <String>['智能洗', '快速洗', '单烘干', '筒清洁']);
      expect(summary.startEntityId, 'button.wm_start_wash_a_2_2');
      expect(summary.pauseEntityId, 'button.wm_pause_a_2_3');
      expect(summary.stopEntityId, 'button.wm_stop_washing_a_2_1');
      expect(summary.energyKwh, 14);
      expect(summary.waterConsumption, 521);
      expect(summary.washedTimes, 85);
      expect(summary.remainingMinutes, isNull, reason: '0 分钟不展示');
      expect(summary.doorState, '舱门已开');
      expect(summary.hasFault, isFalse);
    });

    test('10kg：没有运行状态传感器、故障为「无故障 None」也能识别', () {
      final WasherSummary? summary = WasherSummary.tryBuild(
        deviceId: 'dev_wm10',
        name: '米家互联网直驱洗烘一体机 10kg',
        entities: <HaEntityStateModel>[
          _e('sensor.x_status_p_2_2', '关机中', name: '设备A 状态'),
          _e('sensor.x_stroke_p_3_6', 'None', name: '设备A 行程'),
          _e('sensor.x_fault_p_2_4', '无故障 None', name: '设备A 故障'),
          _e('switch.x_on_p_2_1', 'off', name: '设备A 电源'),
          _e(
            'select.x_mode_p_2_3',
            '未选择模式',
            name: '设备A 模式',
            attributes: <String, dynamic>{
              'options': <String>['日常洗', '快速洗', '单脱水', '未选择模式'],
            },
          ),
          _e('button.x_start_wash_a_2_1', 'unknown', name: '设备A 开始'),
          _e('button.x_pause_a_2_2', 'unknown', name: '设备A 暂停'),
        ],
      );

      expect(summary, isNotNull);
      expect(summary!.isOn, isFalse);
      expect(summary.hasFault, isFalse);
      expect(summary.statusLabel, '已关机');
      expect(summary.startEntityId, 'button.x_start_wash_a_2_1');
      expect(summary.pauseEntityId, 'button.x_pause_a_2_2');
      expect(summary.stopEntityId, isNull);
    });

    test('10kg 运行中：用 stroke 归一化为中文运行状态', () {
      final WasherSummary summary = WasherSummary.tryBuild(
        deviceId: 'dev_wm10',
        name: '10kg',
        entities: <HaEntityStateModel>[
          _e('sensor.x_status_p_2_2', '工作中', name: '状态'),
          _e('sensor.x_stroke_p_3_6', 'Washing', name: '行程'),
          _e('switch.x_on_p_2_1', 'on', name: '电源'),
          _e(
            'select.x_mode_p_2_3',
            '日常洗',
            name: '模式',
            attributes: <String, dynamic>{
              'options': <String>['日常洗', '快速洗'],
            },
          ),
        ],
      )!;
      expect(summary.isRunning, isTrue);
      expect(summary.runStatus, '洗涤中');
      expect(summary.statusLabel, '洗涤中');
    });

    test('运行中：剩余时间与状态文案', () {
      final WasherSummary summary = WasherSummary.tryBuild(
        deviceId: 'dev_wm',
        name: '洗衣机',
        entities: _washerEntities(
          status: '工作中',
          runStatus: '主洗中',
          leftTime: '32',
        ),
      )!;

      expect(summary.isRunning, isTrue);
      expect(summary.remainingMinutes, 32);
      expect(summary.statusLabel, '主洗中 · 剩余 32 分钟');
    });

    test('真实故障会标记 hasFault', () {
      final WasherSummary summary = WasherSummary.tryBuild(
        deviceId: 'dev_wm',
        name: '洗衣机',
        entities: _washerEntities(fault: '门未关好 E2'),
      )!;
      expect(summary.hasFault, isTrue);
    });

    test('缺少工作状态 / 模式的设备不会被误判成洗衣机', () {
      final WasherSummary? summary = WasherSummary.tryBuild(
        deviceId: 'dev_other',
        name: '普通开关',
        entities: <HaEntityStateModel>[
          _e('switch.other_on', 'off', name: '普通开关 开关'),
        ],
      );
      expect(summary, isNull);
    });
  });
}
