import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';
import 'package:pscreen_home/features/home/domain/models/projector_summary.dart';

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
  String startup = '2026-10-18T01:49:00.860+00:00',
  String shutdown = '2026-10-17T17:10:12.491+00:00',
  String appList =
      '{"apps":[{"name":"薯仔看电视","pkg":"screen.potatokid.tools"},'
          '{"name":"云视听小电视","pkg":"com.xiaodianshi.tv.yst"}]}',
}) =>
    <HaEntityStateModel>[
      _e('sensor.jmgo_applist_p_8_2', appList, name: '随便改的应用列表'),
      _e('number.jmgo_volume_p_4_1', '31',
          name: '音量',
          attributes: const <String, dynamic>{
            'min': 0,
            'max': 100,
            'step': 1,
          }),
      _e('number.jmgo_brightness_p_2_3', '10',
          name: '亮度',
          attributes: const <String, dynamic>{
            'min': 1,
            'max': 10,
            'step': 1,
          }),
      _e('select.jmgo_input_control_p_2_2', '媒体中心',
          name: '输入源',
          attributes: const <String, dynamic>{
            'options': <String>['HDMI 1', '媒体中心'],
          }),
      _e('switch.jmgo_mute_p_4_2', 'off', name: '静音'),
      _e('text.jmgo_apppackagename_p_8_1',
          'screen.potatokid.tools', name: '应用包名'),
      _e('notify.jmgo_openapp_a_8_1', 'unknown', name: '打开应用'),
      _e('notify.jmgo_press_button_a_6_1', 'unknown', name: '虚拟遥控'),
      _e('button.jmgo_turn_on_a_7_1', 'unknown', name: '开机'),
      _e('button.jmgo_turn_off_a_2_1', 'unknown', name: '关机'),
      _e('button.jmgo_play_a_3_3', 'unknown', name: '播放'),
      _e('button.jmgo_pause_a_3_4', 'unknown', name: '暂停'),
      _e('button.jmgo_next_a_3_5', 'unknown', name: '下一首'),
      _e('button.jmgo_previous_a_3_6', 'unknown', name: '上一首'),
      _e('button.jmgo_stop_a_3_7', 'unknown', name: '停止'),
      _e('event.jmgo_devicestartup_e_8_2', startup, name: '开机事件'),
      _e('event.jmgo_deviceshutdown_e_8_1', shutdown, name: '关机事件'),
    ];

void main() {
  group('ProjectorSummary', () {
    test('解析音量 / 亮度 / 输入源 / 应用 / 开关机状态', () {
      final ProjectorSummary? summary = ProjectorSummary.tryBuild(
        deviceId: 'dev_proj',
        name: '坚果智能投影仪-N系列',
        entities: _entities(),
      );

      expect(summary, isNotNull);
      expect(summary!.isOn, isTrue, reason: '开机事件晚于关机事件');
      expect(summary.volume, 31);
      expect(summary.brightness, 10);
      expect(summary.inputs, <String>['HDMI 1', '媒体中心']);
      expect(summary.input, '媒体中心');
      expect(summary.mute, isFalse);
      expect(summary.apps.map((ProjectorApp a) => a.name),
          <String>['薯仔看电视', '云视听小电视']);
      expect(summary.currentAppName, '薯仔看电视');
      expect(summary.statusLabel, '薯仔看电视');
      expect(summary.brightnessMax, 10);
      expect(summary.openAppEntityId, 'notify.jmgo_openapp_a_8_1');
      expect(summary.pressButtonEntityId,
          'notify.jmgo_press_button_a_6_1');
      expect(summary.hasRemote, isTrue);
      expect(summary.powerOffEntityId, 'button.jmgo_turn_off_a_2_1');
      expect(summary.hasPlayback, isTrue);
    });

    test('关机事件更晚时判定为关闭', () {
      final ProjectorSummary summary = ProjectorSummary.tryBuild(
        deviceId: 'd',
        name: 'p',
        entities: _entities(
          startup: '2026-10-17T01:00:00+00:00',
          shutdown: '2026-10-18T01:00:00+00:00',
        ),
      )!;
      expect(summary.isOn, isFalse);
      expect(summary.statusLabel, '已关闭');
    });

    test('应用列表 JSON 被 HA 截断到 255 字符时仍解析完整项', () {
      final ProjectorSummary summary = ProjectorSummary.tryBuild(
        deviceId: 'd',
        name: 'p',
        entities: _entities(
          appList: '{"apps":[{"name":"A","pkg":"com.a"},'
              '{"name":"B","pkg":"com.b"},{"name":"C","pkg":"com.c',
        ),
      )!;
      expect(summary.apps.map((ProjectorApp a) => a.package),
          <String>['com.a', 'com.b']);
    });

    test('没有投影仪特征实体时返回 null', () {
      final ProjectorSummary? summary = ProjectorSummary.tryBuild(
        deviceId: 'd',
        name: '风扇',
        entities: <HaEntityStateModel>[
          _e('fan.other', 'on', name: '风扇'),
        ],
      );
      expect(summary, isNull);
    });
  });
}
