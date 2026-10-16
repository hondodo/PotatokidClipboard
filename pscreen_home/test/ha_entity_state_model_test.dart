import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';

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
}
