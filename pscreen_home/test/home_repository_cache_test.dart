import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/core/network/ha_net_exceptions.dart';
import 'package:pscreen_home/core/network/ha_ws_client.dart';
import 'package:pscreen_home/features/home/data/repositories/home_repository_impl.dart';
import 'package:pscreen_home/features/home/domain/models/ha_registry_model.dart';
import 'package:pscreen_home/features/home/domain/repositories/registry_cache.dart';
import 'package:pscreen_screen/core/logging/log_service.dart';

class _FakeHaWsClient extends HaWsClient {
  _FakeHaWsClient({required this.responses, this.fail = false})
    : super(log: const LogService());

  final Map<String, Object?> responses;
  final bool fail;

  @override
  Future<Map<String, dynamic>> request(
    String type, [
    Map<String, dynamic> params = const <String, dynamic>{},
  ]) async {
    if (fail) throw const HaRequestException(null, '模拟超时');
    return <String, dynamic>{'result': responses[type]};
  }
}

class _FakeRegistryCache implements RegistryCache {
  HaRegistry? value;
  int writes = 0;

  @override
  HaRegistry? read() => value;

  @override
  Future<void> write(HaRegistry registry) async {
    value = registry;
    writes++;
  }
}

const HaRegistry _cachedRegistry = HaRegistry(
  areas: <HaArea>[HaArea(areaId: 'cached_area', name: '金科1204 客厅')],
  devices: <String, HaDevice>{
    'cached_dev': HaDevice(id: 'cached_dev', name: '缓存灯'),
  },
  areaIdByEntity: <String, String>{'light.cached': 'cached_area'},
  deviceIdByEntity: <String, String>{'light.cached': 'cached_dev'},
);

void main() {
  group('HomeRepositoryImpl 注册表缓存', () {
    test('拉取成功时返回新表并写入缓存', () async {
      final _FakeRegistryCache cache = _FakeRegistryCache();
      final HomeRepositoryImpl repository = HomeRepositoryImpl(
        client: _FakeHaWsClient(
          responses: <String, Object?>{
            'config/area_registry/list': <Object>[
              <String, dynamic>{
                'area_id': 'jk_kt',
                'name': '金科1204 客厅',
                'position': 1,
              },
            ],
            'config/device_registry/list': <Object>[
              <String, dynamic>{
                'id': 'dev1',
                'name': '客厅灯',
                'area_id': 'jk_kt',
              },
            ],
            'config/entity_registry/list': <Object>[
              <String, dynamic>{
                'entity_id': 'light.living',
                'device_id': 'dev1',
              },
            ],
          },
        ),
        log: const LogService(),
        cache: cache,
      );

      final HaRegistry registry = await repository.fetchRegistry();

      expect(registry.areas.single.name, '金科1204 客厅');
      expect(registry.devices['dev1']?.name, '客厅灯');
      expect(registry.areaIdOf('light.living'), 'jk_kt');
      expect(cache.writes, 1);
      expect(cache.value?.areas.single.areaId, 'jk_kt');
    });

    test('拉取失败时返回缓存，不把空表写回缓存', () async {
      final _FakeRegistryCache cache = _FakeRegistryCache()
        ..value = _cachedRegistry;
      final HomeRepositoryImpl repository = HomeRepositoryImpl(
        client: _FakeHaWsClient(
          responses: const <String, Object?>{},
          fail: true,
        ),
        log: const LogService(),
        cache: cache,
      );

      final HaRegistry registry = await repository.fetchRegistry();

      expect(registry.areas.single.areaId, 'cached_area');
      expect(registry.devices['cached_dev']?.name, '缓存灯');
      expect(cache.writes, 0);
    });

    test('拉取失败且无缓存时降级为空注册表', () async {
      final _FakeRegistryCache cache = _FakeRegistryCache();
      final HomeRepositoryImpl repository = HomeRepositoryImpl(
        client: _FakeHaWsClient(
          responses: const <String, Object?>{},
          fail: true,
        ),
        log: const LogService(),
        cache: cache,
      );

      final HaRegistry registry = await repository.fetchRegistry();

      expect(registry.areas, isEmpty);
      expect(registry.devices, isEmpty);
      expect(cache.writes, 0);
    });
  });
}
