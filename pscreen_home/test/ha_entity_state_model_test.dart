import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';
import 'package:pscreen_home/features/home/domain/models/ha_registry_model.dart';

void main() {
  group('HaEntityStateModel', () {
    HaEntityStateModel buildEntity({
      String entityId = 'light.bedroom_light',
      String state = 'on',
      Map<String, dynamic> attributes = const <String, dynamic>{
        'friendly_name': '卧室大灯',
      },
    }) {
      return HaEntityStateModel(
        entityId: entityId,
        state: state,
        attributes: attributes,
      );
    }

    test('fromJson 解析 HA 实体状态（entity_id 反蛇形命名）', () {
      final HaEntityStateModel entity = HaEntityStateModel.fromJson(
        <String, dynamic>{
          'entity_id': 'switch.air_purifier',
          'state': 'off',
          'attributes': <String, dynamic>{'friendly_name': '空气净化器'},
        },
      );
      expect(entity.entityId, 'switch.air_purifier');
      expect(entity.state, 'off');
      expect(entity.displayName, '空气净化器');
    });

    test('domain / 开关态 / 可用性 / 可控性', () {
      expect(buildEntity().domain, 'light');
      expect(buildEntity().isOn, isTrue);
      expect(buildEntity().isAvailable, isTrue);
      expect(buildEntity().isSwitchable, isTrue);

      expect(buildEntity(state: 'unavailable').isAvailable, isFalse);
      expect(buildEntity(state: 'unavailable').isSwitchable, isFalse);

      expect(
        buildEntity(entityId: 'sensor.temperature', state: 'on').isSwitchable,
        isFalse,
        reason: 'sensor 域不可开关',
      );
    });

    test('displayName 回退：无 friendly_name 时用 entity_id 去域前缀', () {
      final HaEntityStateModel entity = buildEntity(
        attributes: const <String, dynamic>{},
      );
      expect(entity.displayName, 'bedroom_light');
    });

    test('灯光参数：亮度百分比 / 色温范围 / 效果列表', () {
      final HaEntityStateModel entity = buildEntity(
        attributes: const <String, dynamic>{
          'brightness': 204,
          'color_temp_kelvin': 3500,
          'min_color_temp_kelvin': 2700,
          'max_color_temp_kelvin': 5700,
          'supported_color_modes': <String>['color_temp'],
          'effect_list': <String>['明亮模式', '电视模式'],
          'effect': '电视模式',
        },
      );
      expect(entity.isLight, isTrue);
      expect(entity.supportsBrightness, isTrue);
      expect(entity.brightnessPercent, 80);
      expect(entity.supportsColorTemperature, isTrue);
      expect(entity.colorTempKelvin, 3500);
      expect(entity.supportsEffect, isTrue);
      expect(entity.effect, '电视模式');
    });

    test('纯开关灯不显示调光 / 色温能力', () {
      final HaEntityStateModel entity = buildEntity(
        attributes: const <String, dynamic>{
          'supported_color_modes': <String>['onoff'],
        },
      );
      expect(entity.supportsBrightness, isFalse);
      expect(entity.supportsColorTemperature, isFalse);
      expect(entity.supportsEffect, isFalse);
    });

    test('空调参数：温度 / 湿度 / 模式 / 风速 / 摆风', () {
      final HaEntityStateModel entity = buildEntity(
        entityId: 'climate.bedroom',
        state: 'cool',
        attributes: const <String, dynamic>{
          'temperature': 26.5,
          'min_temp': 16,
          'max_temp': 31,
          'target_temp_step': 0.5,
          'current_temperature': 35.0,
          'current_humidity': 55,
          'hvac_modes': <String>['cool', 'heat', 'off'],
          'fan_modes': <String>['自动', '三档'],
          'fan_mode': '三档',
          'swing_modes': <String>['off', 'vertical'],
          'swing_mode': 'off',
        },
      );
      expect(entity.isClimate, isTrue);
      expect(entity.isSwitchable, isTrue);
      expect(entity.isOn, isTrue, reason: 'cool 属于开启');
      expect(entity.targetTemperature, 26.5);
      expect(entity.currentTemperature, 35.0);
      expect(entity.currentHumidity, 55);
      expect(entity.targetTempStep, 0.5);
      expect(entity.hvacMode, 'cool');
      expect(entity.fanModes, <String>['自动', '三档']);
      expect(entity.fanMode, '三档');
      expect(entity.swingModes, <String>['off', 'vertical']);
      expect(entity.swingMode, 'off');

      expect(entity.copyWith(state: 'off').isOn, isFalse);
    });

    test('mergeAttributes 只覆盖给定键', () {
      final HaEntityStateModel entity = buildEntity(
        attributes: const <String, dynamic>{
          'friendly_name': '卧室大灯',
          'brightness': 204,
        },
      );
      final HaEntityStateModel merged =
          entity.mergeAttributes(<String, dynamic>{'brightness': 128});
      expect(merged.brightnessValue, 128);
      expect(merged.displayName, '卧室大灯');
      expect(entity.brightnessValue, 204, reason: '原对象保持不可变');
    });

    test('displayNameWithout 裁剪设备名前缀', () {
      final HaEntityStateModel entity = buildEntity(
        attributes: const <String, dynamic>{
          'friendly_name': '小米空调 开发者模式',
        },
      );
      expect(entity.displayNameWithout('小米空调'), '开发者模式');
      // 前缀不匹配 / 为空时原样返回
      expect(entity.displayNameWithout('别的设备'), '小米空调 开发者模式');
      expect(entity.displayNameWithout(''), '小米空调 开发者模式');
    });

    test('displayNameWithout 裁完为空时保留原名', () {
      final HaEntityStateModel entity = buildEntity(
        attributes: const <String, dynamic>{'friendly_name': '小米空调'},
      );
      expect(entity.displayNameWithout('小米空调'), '小米空调');
    });

    test('withoutDeviceName 返回裁剪副本且不影响原对象', () {
      final HaEntityStateModel entity = buildEntity(
        attributes: const <String, dynamic>{
          'friendly_name': '小米空调 开发者模式',
          'brightness': 128,
        },
      );
      final HaEntityStateModel stripped = entity.withoutDeviceName('小米空调');
      expect(stripped.displayName, '开发者模式');
      expect(stripped.brightnessValue, 128, reason: '其余属性保留');
      expect(entity.displayName, '小米空调 开发者模式', reason: '原对象不变');
    });

    test('withoutDeviceName 无需裁剪时返回同一实例', () {
      final HaEntityStateModel entity = buildEntity(
        attributes: const <String, dynamic>{'friendly_name': '卧室大灯'},
      );
      expect(entity.withoutDeviceName('小米空调'), same(entity));
    });
  });

  group('HaArea 家庭/房间拆分', () {
    test('首个空格前为家庭名', () {
      const HaArea area =
          HaArea(areaId: 'jin_ke_1204_ke_ting', name: '金科1204 客厅');
      expect(area.homeName, '金科1204');
      expect(area.roomName, '客厅');
    });

    test('家庭名外的部分整体作为房间名', () {
      const HaArea area =
          HaArea(areaId: 'shu_zi_4hao_de_jia_1lou_chu_fang', name: '薯仔4号的家 1楼厨房');
      expect(area.homeName, '薯仔4号的家');
      expect(area.roomName, '1楼厨房');
    });

    test('无空格视为未分配家庭，房间名等于区域名', () {
      const HaArea area = HaArea(areaId: 'ke_ting', name: '客厅');
      expect(area.homeName, '');
      expect(area.roomName, '客厅');
    });

    test('HaRegistry 归属解析：命中返回完整区域名，未收录返回 null', () {
      const HaRegistry registry = HaRegistry(
        areas: <HaArea>[HaArea(areaId: 'jk_kt', name: '金科1204 客厅')],
        areaIdByEntity: <String, String>{'light.a': 'jk_kt'},
      );
      expect(registry.areaNameOf('light.a'), '金科1204 客厅');
      expect(registry.areaNameOf('light.b'), isNull);
    });
  });
}
