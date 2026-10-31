import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/features/home/data/cache/file_home_state_cache.dart';
import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';
import 'package:pscreen_screen/core/logging/log_service.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('ha_home_state_cache');
  });

  tearDown(() async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  FileHomeStateCache cache({String host = '192.168.1.2:8123'}) {
    return FileHomeStateCache(
      log: const LogService(),
      hostProvider: () => host,
      directoryProvider: () async => directory,
    );
  }

  test('快照写入后可按原样读回', () async {
    final DateTime changed = DateTime.utc(2026, 1, 2, 3, 4, 5);
    final List<HaEntityStateModel> states = <HaEntityStateModel>[
      HaEntityStateModel(
        entityId: 'light.bedroom',
        state: 'on',
        attributes: <String, dynamic>{
          'friendly_name': '卧室灯',
          'brightness': 128,
        },
        lastChanged: changed,
      ),
      HaEntityStateModel(
        entityId: 'sensor.temperature',
        state: '24.5',
        attributes: <String, dynamic>{'unit_of_measurement': '°C'},
      ),
    ];

    await cache().write(states);
    final List<HaEntityStateModel>? restored = await cache().read();

    expect(restored, isNotNull);
    expect(restored!.length, 2);
    expect(restored.first.entityId, 'light.bedroom');
    expect(restored.first.attributes['friendly_name'], '卧室灯');
    expect(restored.first.attributes['brightness'], 128);
    expect(restored.first.lastChanged, changed);
    expect(restored.last.entityId, 'sensor.temperature');
  });

  test('HA 地址不匹配时忽略快照', () async {
    await cache(host: '192.168.1.2:8123').write(<HaEntityStateModel>[
      HaEntityStateModel(
        entityId: 'light.bedroom',
        state: 'on',
        attributes: const <String, dynamic>{},
      ),
    ]);

    expect(await cache(host: '192.168.1.9:8123').read(), isNull);
    expect(await cache(host: 'http://192.168.1.2:8123/').read(), isNotNull);
  });

  test('快照文件损坏时忽略并返回 null', () async {
    await cache().write(<HaEntityStateModel>[
      HaEntityStateModel(
        entityId: 'light.bedroom',
        state: 'on',
        attributes: const <String, dynamic>{},
      ),
    ]);
    final List<FileSystemEntity> files = await directory
        .list()
        .where((FileSystemEntity entity) => entity.path.endsWith('.json.gz'))
        .toList();
    expect(files, hasLength(1));
    await File(files.single.path).writeAsBytes(<int>[1, 2, 3]);

    expect(await cache().read(), isNull);
  });

  test('空实体列表不写快照', () async {
    await cache().write(<HaEntityStateModel>[]);
    expect(await directory.list().toList(), isEmpty);
  });
}
