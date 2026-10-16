import 'package:flutter/widgets.dart';
import 'package:home_assistant/home_assistant.dart';

import 'home_assistant_registry.dart';

class HomeAssistantUtil {
  static const String baseUrl = 'http://localhost:8123';
  static const String bearerToken =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiI4MzRlOTAyN2NiYWQ0MzViOTZhN2MwYjEwNmFkNzUxZCIsImlhdCI6MTc5MjExNjI1OCwiZXhwIjoyMTA3NDc2MjU4fQ.JjekTQ0EB8iqUopiul1JtR8rv-G6EPi0ROdRJ5BA5Hg';

  Future test() async {
    // Initialize the Home Assistant instance.
    final homeAssistant = HomeAssistant(
      baseUrl: baseUrl,
      bearerToken: bearerToken,
    );

    // Verify if the Home Assistant API is working.
    final isApiWorking = await homeAssistant.verifyApiIsWorking();
    if (isApiWorking) {
      debugPrint('Home Assistant API is working.');
    } else {
      debugPrint('Home Assistant API is not working.');
    }

    // Fetch a list of entities.
    final entities = await homeAssistant.fetchStates();
    debugPrint('Entities: ${entities.length}');
    // for (var entity in entities) {
    //   debugPrint(
    //     'Entity: ${entity.entityId} ${entity.state} ${entity.lastUpdated} ${entity.lastReported} ${entity.lastChanged} ${entity.context.id}  ${entity.context.parentId}  ${entity.context.userId}\n',
    //   );
    // }

    // Control an Entity / Execute a service.

    // Example of a switch:
    final success = await homeAssistant.executeService(
      'button.cuco_cn_783193359_v3_toggle_a_2_1',
      'press',
      additionalActions: {},
    );
    if (success) {
      debugPrint('Switch turned on.');
    } else {
      debugPrint('Failed to turn on the switch');
    }
    final entity = await homeAssistant.fetchState(
      'sensor.cuco_cn_783193359_v3_power_consumption_p_11_1',
    );

    debugPrint(
      'Entity: entityId:${entity.entityId} state:${entity.state} lastUpdated:${entity.lastUpdated} lastReported:${entity.lastReported} lastChanged:${entity.lastChanged} ${entity.context.id}  ${entity.context.parentId}  ${entity.context.userId}\n',
    );

    // // Example of a light:
    // final success = await homeAssistant.executeService(
    //     'light.entity_id',
    //     'turn_on',
    //     additionalActions: {'brightness': 255},
    // );
    // if (success) {
    //   print('Light turned on with brightness.');
    // } else {
    //   print('Failed to turn on the light: $e');
    // }

    // // Example of a climate device:
    // final success = await homeAssistant.executeService(
    //     await homeAssistant.executeService(
    //         'climate.entity_id',
    //         'set_temperature',
    //         additionalActions: {
    //           'temperature': 22,
    //           'hvac_mode': 'heat', // Optional: specify HVAC mode if needed
    //         },
    // );
    // if (success) {
    //     print('Temperature set to 22 degrees.');
    // } else {
    //     print('Failed to set temperature: $e');
    // }
  }

  /// 走 WebSocket 拉取设备注册表，按「设备 → 实体」列出，例如 阳台植物灯。
  Future testRegistry() async {
    final snapshot = await HomeAssistantRegistry(
      baseUrl: baseUrl,
      bearerToken: bearerToken,
    ).load();

    debugPrint('设备总数: ${snapshot.devices.length}');

    // 按设备名查找，拿到的就是它名下的全部实体
    for (final device in snapshot.findDevices('灯')) {
      debugPrint(
        '设备: ${device.name}  型号: ${device.model}  '
        '标识: ${device.identifiers}  实体数: ${device.entities.length}',
      );
      for (final entity in device.entities) {
        debugPrint(
          '   - ${entity.entityId}  ${entity.name}  '
          'state=${entity.state}',
        );
      }
    }
  }
}
