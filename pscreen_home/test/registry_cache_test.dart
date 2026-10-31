import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/core/di/get_it.dart';
import 'package:pscreen_home/core/storage/settings_store.dart';
import 'package:pscreen_home/features/home/data/cache/settings_registry_cache.dart';
import 'package:pscreen_home/features/home/domain/models/ha_registry_model.dart';
import 'package:pscreen_screen/core/logging/log_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const HaRegistry _sample = HaRegistry(
  areas: <HaArea>[
    HaArea(areaId: 'jk_kt', name: '金科1204 客厅', position: 1),
    HaArea(areaId: 'jk_ws', name: '金科1204 卧室', position: 2),
  ],
  devices: <String, HaDevice>{
    'dev1': HaDevice(id: 'dev1', name: '客厅灯', areaId: 'jk_kt'),
    'dev2': HaDevice(id: 'dev2', name: '卧室灯'),
  },
  areaIdByEntity: <String, String>{
    'light.living': 'jk_kt',
    'light.bedroom': 'jk_ws',
  },
  deviceIdByEntity: <String, String>{
    'light.living': 'dev1',
    'light.bedroom': 'dev2',
  },
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    getIt.registerLazySingleton<LogService>(() => const LogService());
  });

  tearDown(() async {
    await getIt.reset();
  });

  group('SettingsRegistryCache', () {
    test('成功写入后可跨实例读回房间 / 设备 / 归属', () async {
      final SettingsStore store = SettingsStore();
      await store.init();
      final SettingsRegistryCache cache = SettingsRegistryCache(
        store: store,
        log: const LogService(),
        hostProvider: () => 'http://ha.local:8123/',
      );

      await cache.write(_sample);

      final SettingsStore next = SettingsStore();
      await next.init();
      final SettingsRegistryCache nextCache = SettingsRegistryCache(
        store: next,
        log: const LogService(),
        hostProvider: () => 'ha.local:8123',
      );
      final HaRegistry? loaded = nextCache.read();
      expect(loaded, isNotNull);
      expect(
        loaded!.areas.map((HaArea area) => '${area.areaId}:${area.name}'),
        <String>['jk_kt:金科1204 客厅', 'jk_ws:金科1204 卧室'],
      );
      expect(loaded.devices['dev1']?.name, '客厅灯');
      expect(loaded.devices['dev1']?.areaId, 'jk_kt');
      expect(loaded.devices['dev2']?.areaId, isNull);
      expect(loaded.areaIdOf('light.bedroom'), 'jk_ws');
      expect(loaded.deviceIdOf('light.living'), 'dev1');
    });

    test('HA 地址不同时不使用旧缓存', () async {
      final SettingsStore store = SettingsStore();
      await store.init();
      final SettingsRegistryCache cache = SettingsRegistryCache(
        store: store,
        log: const LogService(),
        hostProvider: () => 'ha-a.local:8123',
      );
      await cache.write(_sample);

      final SettingsRegistryCache other = SettingsRegistryCache(
        store: store,
        log: const LogService(),
        hostProvider: () => 'ha-b.local:8123',
      );
      expect(other.read(), isNull);
    });

    test('缓存损坏或版本不匹配时忽略', () async {
      final SettingsStore store = SettingsStore();
      await store.init();
      final SettingsRegistryCache cache = SettingsRegistryCache(
        store: store,
        log: const LogService(),
        hostProvider: () => 'ha.local:8123',
      );

      await store.saveRegistryCacheRaw('{not-json');
      expect(cache.read(), isNull);

      await store.saveRegistryCacheRaw(
        jsonEncode(<String, dynamic>{
          'version': 999,
          'host': 'ha.local:8123',
          'areas': <Object>[
            <String, dynamic>{'id': 'a1', 'name': '金科1204 客厅'},
          ],
        }),
      );
      expect(cache.read(), isNull);
    });

    test('空注册表不会覆盖已有缓存', () async {
      final SettingsStore store = SettingsStore();
      await store.init();
      final SettingsRegistryCache cache = SettingsRegistryCache(
        store: store,
        log: const LogService(),
        hostProvider: () => 'ha.local:8123',
      );
      await cache.write(_sample);

      await cache.write(HaRegistry.empty);

      expect(cache.read()?.areas.length, 2);
    });

    test('仅缺少房间时缓存不可用', () async {
      final SettingsStore store = SettingsStore();
      await store.init();
      final SettingsRegistryCache cache = SettingsRegistryCache(
        store: store,
        log: const LogService(),
        hostProvider: () => 'ha.local:8123',
      );

      await cache.write(
        const HaRegistry(
          devices: <String, HaDevice>{
            'dev1': HaDevice(id: 'dev1', name: '客厅灯'),
          },
        ),
      );

      expect(cache.read(), isNull);
    });
  });
}
