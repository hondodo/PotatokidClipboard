import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/core/di/get_it.dart';
import 'package:pscreen_screen/core/logging/log_service.dart';
import 'package:pscreen_home/core/storage/settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    getIt.registerLazySingleton<LogService>(() => const LogService());
  });

  tearDown(() async {
    await getIt.reset();
  });

  group('SettingsStore 持久化', () {
    test('初始无覆盖', () async {
      final SettingsStore store = SettingsStore();
      await store.init();

      expect(store.hostOverride, '');
      expect(store.tokenOverride, '');
    });

    test('保存后可读，且跨实例持久化', () async {
      final SettingsStore store = SettingsStore();
      await store.init();
      await store.save(host: '192.168.1.10:8123', token: 'my_token');

      expect(store.hostOverride, '192.168.1.10:8123');
      expect(store.tokenOverride, 'my_token');

      // 模拟下次启动：新实例读到同样的值
      final SettingsStore next = SettingsStore();
      await next.init();
      expect(next.hostOverride, '192.168.1.10:8123');
      expect(next.tokenOverride, 'my_token');
    });

    test('空字符串保存 = 删除覆盖（回落 .env 的语义）', () async {
      final SettingsStore store = SettingsStore();
      await store.init();
      await store.save(host: '10.0.0.2:8123', token: 'x');

      await store.save(host: '', token: '');

      expect(store.hostOverride, '');
      expect(store.tokenOverride, '');

      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(SettingsStore.hostKey), isFalse);
      expect(prefs.containsKey(SettingsStore.tokenKey), isFalse);
    });

    test('地址与令牌可独立覆盖（只清地址保留令牌）', () async {
      final SettingsStore store = SettingsStore();
      await store.init();
      await store.save(host: '10.0.0.2:8123', token: 'my_token');

      await store.save(host: '', token: 'my_token');

      expect(store.hostOverride, '');
      expect(store.tokenOverride, 'my_token');
    });

    test('功率采样间隔默认 5 秒，保存后跨实例生效', () async {
      final SettingsStore store = SettingsStore();
      await store.init();
      expect(store.powerSampleSeconds,
          SettingsStore.defaultPowerSampleSeconds);

      await store.savePowerSampleSeconds(10);
      expect(store.powerSampleSeconds, 10);

      final SettingsStore next = SettingsStore();
      await next.init();
      expect(next.powerSampleSeconds, 10);
    });

    test('保存默认间隔 = 删除键，非法值回落默认', () async {
      final SettingsStore store = SettingsStore();
      await store.init();
      await store.savePowerSampleSeconds(30);
      expect(store.powerSampleSeconds, 30);

      await store.savePowerSampleSeconds(
          SettingsStore.defaultPowerSampleSeconds);
      expect(store.powerSampleSeconds,
          SettingsStore.defaultPowerSampleSeconds);

      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(SettingsStore.powerSampleSecondsKey), isFalse);

      await store.savePowerSampleSeconds(7);
      expect(store.powerSampleSeconds,
          SettingsStore.defaultPowerSampleSeconds);
    });
  });
}
