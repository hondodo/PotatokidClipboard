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
