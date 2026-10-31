import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/features/home/domain/models/ha_device_group.dart';
import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';

HaEntityStateModel _entity(
  String entityId,
  String state, {
  String? name,
}) =>
    HaEntityStateModel(
      entityId: entityId,
      state: state,
      attributes: <String, dynamic>{
        'friendly_name': ?name,
      },
    );

/// 分组入口：id 含 `shared` 的实体同属一个设备（dev_shared），其余无归属各自成组。
List<HaDeviceGroup> _group(Map<String, HaEntityStateModel> entities) =>
    HaDeviceGroup.group(
      entities: entities,
      deviceIdOf: (String entityId) =>
          entityId.contains('shared') ? 'dev_shared' : null,
      deviceNameOf: (String deviceId) =>
          deviceId == 'dev_shared' ? '阳台植物灯' : null,
    );

void main() {
  group('HaDeviceGroup.group', () {
    test('同设备多实体合并为一组，无归属实体各自成组', () {
      final List<HaDeviceGroup> groups = _group(<String, HaEntityStateModel>{
        for (final HaEntityStateModel e in <HaEntityStateModel>[
          _entity('light.shared_main', 'on'),
          _entity('switch.shared_a', 'off'),
          _entity('switch.lonely', 'off'),
        ])
          e.entityId: e,
      });

      expect(groups.length, 2, reason: '同设备 2 个实体应合并，孤独开关自成一组');
      final HaDeviceGroup merged = groups
          .firstWhere((HaDeviceGroup g) => g.deviceId == 'dev_shared');
      expect(merged.title, '阳台植物灯', reason: '设备名优先于实体名');
      expect(
        merged.entities.map((HaEntityStateModel e) => e.entityId).toSet(),
        <String>{'light.shared_main', 'switch.shared_a'},
      );

      final HaDeviceGroup lonely = groups
          .firstWhere((HaDeviceGroup g) => g.deviceId == null);
      expect(lonely.title, 'lonely', reason: '无设备时用主实体显示名（去域前缀）');
      expect(lonely.entities.single.entityId, 'switch.lonely');
    });

    test('主实体选取：真灯 > switch > 指示灯类 light', () {
      // 真灯优先于同设备的 switch
      final HaDeviceGroup lightDevice = _group(<String, HaEntityStateModel>{
        for (final HaEntityStateModel e in <HaEntityStateModel>[
          _entity('switch.shared_a', 'on'),
          _entity('light.shared_main', 'off', name: '风扇灯 灯'),
          _entity('light.shared_night_light', 'on', name: '风扇灯 夜灯'),
        ])
          e.entityId: e,
      }).first;
      expect(lightDevice.primary!.entityId, 'light.shared_main');
      expect(
        lightDevice.entities.first.entityId,
        'light.shared_main',
        reason: '主实体必须排在组内首位',
      );

      // 插座类设备：指示灯 light 不当选主实体，电源 switch 才是
      final HaDeviceGroup plugDevice = _group(<String, HaEntityStateModel>{
        for (final HaEntityStateModel e in <HaEntityStateModel>[
          _entity('light.shared_indicator', 'on', name: '阳台植物灯 指示灯'),
          _entity('switch.shared_power', 'off', name: '阳台植物灯 开关'),
        ])
          e.entityId: e,
      }).first;
      expect(plugDevice.primary!.entityId, 'switch.shared_power');
    });

    test('主实体选取：优先真正电源开关，而不是提示音 / 静音', () {
      final HaDeviceGroup washer = _group(<String, HaEntityStateModel>{
        for (final HaEntityStateModel e in <HaEntityStateModel>[
          _entity(
            'switch.shared_alarm_p_4_1',
            'on',
            name: '米家洗衣机 洗烘12kg  提示音 提示音',
          ),
          _entity(
            'switch.shared_on_p_2_1',
            'off',
            name: '米家洗衣机 洗烘12kg  洗衣机 开关',
          ),
          _entity(
            'switch.shared_sleep_p_2_23',
            'off',
            name: '米家洗衣机 洗烘12kg  洗衣机 睡眠模式',
          ),
          _entity(
            'switch.shared_one_click_p_2_33',
            'off',
            name: '米家洗衣机 洗烘12kg  洗衣机 一键智能洗功能',
          ),
        ])
          e.entityId: e,
      }).first;

      expect(washer.primary!.entityId, 'switch.shared_on_p_2_1');
      expect(washer.primary!.displayName, contains('开关'));
      expect(
        washer.entities.first.entityId,
        'switch.shared_on_p_2_1',
        reason: '主电源必须排在组内首位',
      );
    });

    test('高水位开关不会被误判成主电源', () {
      final HaDeviceGroup washer = _group(<String, HaEntityStateModel>{
        for (final HaEntityStateModel e in <HaEntityStateModel>[
          _entity(
            'switch.shared_high_water_p_2_19',
            'off',
            name: '米家洗衣机 洗烘12kg  洗衣机 高水位开关',
          ),
          _entity(
            'switch.shared_on_p_2_1',
            'off',
            name: '米家洗衣机 洗烘12kg  洗衣机 开关',
          ),
        ])
          e.entityId: e,
      }).first;
      expect(washer.primary!.entityId, 'switch.shared_on_p_2_1');
    });

    test('全实体分组：纯数据/动作设备 primary 为空，状态显示可用数', () {
      final HaDeviceGroup group = _group(<String, HaEntityStateModel>{
        for (final HaEntityStateModel e in <HaEntityStateModel>[
          _entity('sensor.shared_temp', '24.5', name: '阳台温度'),
          _entity('binary_sensor.shared_motion', 'off', name: '阳台人体'),
          _entity('button.shared_action', 'unknown', name: '阳台按钮'),
        ])
          e.entityId: e,
      }).first;

      expect(group.isMerged, isTrue);
      expect(group.primary, isNull, reason: '没有可开关实体');
      expect(group.isUnavailable, isFalse);
      expect(group.availableCount, 2);
      expect(group.statusLabel, '可用 2/3',
          reason: 'unknown 的 button 不可用，但仍占一个实体');
      expect(group.isTogglingIn(<String>{}), isFalse);
    });

    test('开关 + 传感器：主实体仍是开关，传感器排在组内后面', () {
      final HaDeviceGroup group = _group(<String, HaEntityStateModel>{
        for (final HaEntityStateModel e in <HaEntityStateModel>[
          _entity('sensor.shared_temp', '24.5', name: '阳台温度'),
          _entity('switch.shared_power', 'on', name: '阳台植物灯 开关'),
        ])
          e.entityId: e,
      }).first;

      expect(group.primary!.entityId, 'switch.shared_power');
      expect(group.statusLabel, '已开启 1/1');
      expect(group.entities.last.entityId, 'sensor.shared_temp',
          reason: '数据类实体排在开关之后');
    });

    test('聚合状态：已关闭 / 已开启 x/y', () {
      final Map<String, HaEntityStateModel> entities = <String, HaEntityStateModel>{
        for (final HaEntityStateModel e in <HaEntityStateModel>[
          _entity('light.shared_main', 'on'),
          _entity('switch.shared_a', 'off'),
          _entity('switch.shared_b', 'on'),
        ])
          e.entityId: e,
      };

      HaDeviceGroup group = _group(entities).first;
      expect(group.onCount, 2);
      expect(group.anyOn, isTrue);
      expect(group.allOff, isFalse);
      expect(group.statusLabel, '已开启 2/3');
      expect(group.isMerged, isTrue);
      expect(group.isTogglingIn(<String>{'switch.shared_a'}), isTrue);
      expect(group.isTogglingIn(<String>{'other'}), isFalse);

      // 全关后聚合状态变为「已关闭」
      final Map<String, HaEntityStateModel> allOff = <String, HaEntityStateModel>{
        for (final HaEntityStateModel e in entities.values)
          e.entityId: e.copyWith(state: 'off'),
      };
      group = _group(allOff).first;
      expect(group.statusLabel, '已关闭');
    });

    test('分组排序：灯类设备在前，其余按设备名', () {
      final List<HaDeviceGroup> groups = _group(<String, HaEntityStateModel>{
        for (final HaEntityStateModel e in <HaEntityStateModel>[
          _entity('switch.solo_b', 'off'),
          _entity('light.shared_main', 'off', name: '吊灯'),
          _entity('switch.solo_a', 'off'),
        ])
          e.entityId: e,
      });

      expect(groups.first.primary!.domain, 'light', reason: '灯类设备排最前');
      expect(
        groups.skip(1).map((HaDeviceGroup g) => g.title).toList(),
        <String>['solo_a', 'solo_b'],
        reason: '非灯设备按名称排序',
      );
    });

    test('空实体表返回空分组列表', () {
      expect(_group(<String, HaEntityStateModel>{}), isEmpty);
    });
  });
}
