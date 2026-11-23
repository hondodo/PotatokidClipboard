import 'package:flutter_test/flutter_test.dart';

import 'package:pscreen_home/core/server/server_api.dart';

void main() {
  group('ServerDeviceConfig 字典版本下发', () {
    test('config 帧解析出 deviceTypesUpdatedAt（缺失时为 0）', () {
      final ServerDeviceConfig full = ServerDeviceConfig.fromJson(<String, dynamic>{
        'homes': <String>['客厅'],
        'source': 'admin',
        'owner': 'u1',
        'layoutKey': 'device_abc',
        'layoutUpdatedAt': 111,
        'programsUpdatedAt': 222,
        'deviceTypesUpdatedAt': 1795421522570,
      });
      expect(full.deviceTypesUpdatedAt, 1795421522570);

      final ServerDeviceConfig old = ServerDeviceConfig.fromJson(<String, dynamic>{
        'homes': null,
      });
      expect(old.deviceTypesUpdatedAt, 0,
          reason: '旧服务端不下发该字段时不应触发热更新');
    });

    test('新旧 config 帧版本号变化可被识别', () {
      final ServerDeviceConfig a = ServerDeviceConfig.fromJson(<String, dynamic>{
        'deviceTypesUpdatedAt': 100,
      });
      final ServerDeviceConfig b = ServerDeviceConfig.fromJson(<String, dynamic>{
        'deviceTypesUpdatedAt': 101,
      });
      expect(b.deviceTypesUpdatedAt > a.deviceTypesUpdatedAt, isTrue);
    });
  });
}
