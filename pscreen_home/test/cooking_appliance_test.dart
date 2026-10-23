import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/features/home/domain/models/air_fryer_summary.dart';
import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';
import 'package:pscreen_home/features/home/domain/models/rice_cooker_summary.dart';

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

void main() {
  group('RiceCookerSummary', () {
    test('解析状态 / 剩余时长 / 食谱 / 开始停止', () {
      final RiceCookerSummary? summary = RiceCookerSummary.tryBuild(
        deviceId: 'dev_rice',
        name: '米家智能微压IH电饭煲3L',
        entities: <HaEntityStateModel>[
          _e('sensor.chunmi_status_p_2_1', '待机中', name: '状态'),
          _e('sensor.chunmi_fault_p_2_2', 'No Faults', name: '故障'),
          _e('sensor.chunmi_menu_id_p_3_1', '1', name: '食谱'),
          _e('sensor.chunmi_left_time_p_3_3', '3593', name: '剩余'),
          _e('sensor.chunmi_cook_total_time_p_3_2', '60', name: '总时长'),
          _e('sensor.chunmi_keepwarm_time_p_3_4', '0', name: '保温时长'),
          _e('binary_sensor.chunmi_auto_keepwarm_flag_p_3_5', 'on',
              name: '自动保温'),
          _e('notify.chunmi_start_cook_a_2_1', 'unknown', name: '开始'),
          _e('button.chunmi_cancel_cooking_a_2_2', 'unknown', name: '停止'),
          _e('event.chunmi_cooking_finished_e_2_1', 'unknown', name: '烹饪完成'),
        ],
      );

      expect(summary, isNotNull);
      expect(summary!.status, '待机中');
      expect(summary.menuId, 1);
      expect(summary.remainingMinutes, 60);
      expect(summary.autoKeepWarm, isTrue);
      expect(summary.hasFault, isFalse);
      expect(summary.isActive, isFalse);
      expect(summary.startMessage, '[1]');
      expect(summary.startEntityId, 'notify.chunmi_start_cook_a_2_1');
      expect(summary.stopEntityId, 'button.chunmi_cancel_cooking_a_2_2');
    });

    test('电热水瓶实体不会被误判为电饭煲', () {
      final RiceCookerSummary? summary = RiceCookerSummary.tryBuild(
        deviceId: 'dev_kettle',
        name: '米家智能电热水瓶 5L',
        entities: <HaEntityStateModel>[
          _e('sensor.mek01_status_p_2_1', '待机中', name: '热水瓶 工作状态'),
          _e('sensor.mek01_temperature_p_2_6', '51', name: '热水瓶 温度'),
          _e('sensor.mek01_fault_p_2_4', '无故障', name: '热水瓶 故障'),
          _e(
            'select.mek01_mode_p_2_3',
            '自来水',
            name: '热水瓶 模式',
            attributes: const <String, dynamic>{
              'options': <String>['自来水', '纯净水', '凉白开'],
            },
          ),
          _e('notify.mek01_start_cook_a_2_1', 'unknown', name: '热水瓶 开始加热'),
          _e('button.mek01_cancel_cooking_a_2_2', 'unknown', name: '热水瓶 停止'),
        ],
      );

      expect(summary, isNull);
    });

    test('仅暴露状态/开始/停止的旧电饭煲仍可识别', () {
      final RiceCookerSummary? summary = RiceCookerSummary.tryBuild(
        deviceId: 'dev_old_rice',
        name: '电饭煲',
        entities: <HaEntityStateModel>[
          _e('sensor.old_status_p_2_1', '待机中', name: '电饭煲 工作状态'),
          _e('notify.old_start_cook_a_2_1', 'unknown', name: '电饭煲 开始烹饪'),
          _e('button.old_cancel_cooking_a_2_2', 'unknown', name: '电饭煲 停止烹饪'),
          _e('event.old_cooking_finished_e_2_1', 'unknown', name: '电饭煲 烹饪完成'),
        ],
      );

      expect(summary, isNotNull);
      expect(summary!.status, '待机中');
    });
  });

  group('AirFryerSummary', () {
    test('解析模式 / 温度 / 时间 / 动作', () {
      final AirFryerSummary? summary = AirFryerSummary.tryBuild(
        deviceId: 'dev_air',
        name: '米家智能空气炸锅P1 6.5L',
        entities: <HaEntityStateModel>[
          _e('sensor.maf_status_p_2_2', '关机中', name: '状态'),
          _e('sensor.maf_fault_p_2_3', '无错误', name: '故障'),
          _e('sensor.maf_left_time_p_2_22', '3', name: '剩余'),
          _e('select.maf_mode_p_2_25', '手动模式',
              name: '模式',
              attributes: const <String, dynamic>{
                'options': <String>['手动模式', '薯条', '鸡翅'],
              }),
          _e('number.maf_target_temperature_p_2_7', '80',
              name: '温度',
              attributes: const <String, dynamic>{
                'min': 40,
                'max': 230,
                'step': 5,
              }),
          _e('number.maf_target_time_p_2_5', '8',
              name: '时间',
              attributes: const <String, dynamic>{
                'min': 1,
                'max': 1440,
                'step': 1,
              }),
          _e('switch.maf_auto_keep_warm_p_2_23', 'on', name: '自动保温'),
          _e('switch.maf_current_keep_warm_p_2_24', 'on', name: '当前保温'),
          _e('button.maf_start_cook_a_2_1', 'unknown', name: '开始'),
          _e('button.maf_pause_a_2_7', 'unknown', name: '暂停'),
          _e('button.maf_resume_cook_a_2_8', 'unknown', name: '继续'),
          _e('button.maf_cancel_cooking_a_2_6', 'unknown', name: '停止'),
        ],
      );

      expect(summary, isNotNull);
      expect(summary!.mode, '手动模式');
      expect(summary.modes.length, 3);
      expect(summary.temperature, 80);
      expect(summary.temperatureStep, 5);
      expect(summary.minutes, 8);
      expect(summary.remainingMinutes, 3);
      expect(summary.autoKeepWarm, isTrue);
      expect(summary.currentKeepWarm, isTrue);
      expect(summary.isActive, isFalse);
      expect(summary.startEntityId, 'button.maf_start_cook_a_2_1');
      expect(summary.stopEntityId, 'button.maf_cancel_cooking_a_2_6');
    });

    test('速烤中 / 烤制中识别为运行状态', () {
      AirFryerSummary build(String status) => AirFryerSummary.tryBuild(
            deviceId: 'd',
            name: 'f',
            entities: <HaEntityStateModel>[
              _e('sensor.maf_status_p_2_2', status, name: '状态'),
              _e('select.maf_mode_p_2_25', '手动模式',
                  name: '模式',
                  attributes: const <String, dynamic>{
                    'options': <String>['手动模式', '薯条'],
                  }),
              _e('number.maf_target_temperature_p_2_7', '80',
                  name: '温度'),
              _e('number.maf_target_time_p_2_5', '8', name: '时间'),
            ],
          )!;
      expect(build('速烤中').isActive, isTrue);
      expect(build('关机中').isActive, isFalse);
      expect(build('待机中').isActive, isFalse);
      expect(build('烹饪完成').isActive, isFalse);
    });
  });
}
