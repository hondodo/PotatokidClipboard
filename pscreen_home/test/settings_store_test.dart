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
      expect(store.powerSampleSeconds, SettingsStore.defaultPowerSampleSeconds);

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
        SettingsStore.defaultPowerSampleSeconds,
      );
      expect(store.powerSampleSeconds, SettingsStore.defaultPowerSampleSeconds);

      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(SettingsStore.powerSampleSecondsKey), isFalse);

      await store.savePowerSampleSeconds(7);
      expect(store.powerSampleSeconds, SettingsStore.defaultPowerSampleSeconds);
    });

    test('卡片顺序跨实例持久化（全部 + 每个家庭）', () async {
      final SettingsStore store = SettingsStore();
      await store.init();
      await store.saveCardOrders(
        all: <String>['device:a', 'device:b'],
        byHome: <String, List<String>>{
          '金科1204': <String>['device:a'],
          '棠德304': <String>['device:b'],
        },
      );

      final SettingsStore next = SettingsStore();
      await next.init();
      expect(next.cardOrderAll, <String>['device:a', 'device:b']);
      expect(next.cardOrderByHome['金科1204'], <String>['device:a']);
      expect(next.cardOrderByHome['棠德304'], <String>['device:b']);
    });

    test('家庭顺序 JSON 损坏时回退空 Map', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        SettingsStore.cardOrderByHomeKey: '{not-json',
      });
      final SettingsStore store = SettingsStore();
      await store.init();
      expect(store.cardOrderByHome, isEmpty);
    });

    test('屏保时长默认 10 分钟，保存后跨实例生效', () async {
      final SettingsStore store = SettingsStore();
      await store.init();
      expect(store.screensaverMinutes, SettingsStore.defaultScreensaverMinutes);

      await store.saveScreensaverMinutes(15);
      expect(store.screensaverMinutes, 15);

      final SettingsStore next = SettingsStore();
      await next.init();
      expect(next.screensaverMinutes, 15);
    });

    test('屏保可选「从不」并跨实例持久化', () async {
      final SettingsStore store = SettingsStore();
      await store.init();

      await store.saveScreensaverMinutes(SettingsStore.screensaverNeverMinutes);
      expect(store.screensaverMinutes, SettingsStore.screensaverNeverMinutes);
      expect(
        SettingsStore.screensaverOptions,
        contains(SettingsStore.screensaverNeverMinutes),
      );

      final SettingsStore next = SettingsStore();
      await next.init();
      expect(next.screensaverMinutes, SettingsStore.screensaverNeverMinutes);
    });

    test('屏保保存默认值删除键，非法值回落默认', () async {
      final SettingsStore store = SettingsStore();
      await store.init();

      await store.saveScreensaverMinutes(30);
      expect(store.screensaverMinutes, 30);

      await store.saveScreensaverMinutes(
        SettingsStore.defaultScreensaverMinutes,
      );
      expect(store.screensaverMinutes, SettingsStore.defaultScreensaverMinutes);
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(SettingsStore.screensaverMinutesKey), isFalse);

      await store.saveScreensaverMinutes(7);
      expect(store.screensaverMinutes, SettingsStore.defaultScreensaverMinutes);
    });

    test('屏保壁纸默认开启、真实风景 API、30 分钟', () async {
      final SettingsStore store = SettingsStore();
      await store.init();

      expect(store.wallpaperEnabled, isTrue);
      expect(store.wallpaperApiUrl, SettingsStore.defaultWallpaperApiUrl);
      expect(store.wallpaperApiUrl, contains('fengjing.php'));
      expect(store.wallpaperMinutes, 30);
      expect(
        SettingsStore.wallpaperMinuteOptions,
        containsAll(<int>[5, 10, 30, 60, 720, 1440]),
      );
    });

    test('壁纸开关跨实例持久化，恢复默认时删除键', () async {
      final SettingsStore store = SettingsStore();
      await store.init();

      await store.saveWallpaperEnabled(false);
      expect(store.wallpaperEnabled, isFalse);

      final SettingsStore next = SettingsStore();
      await next.init();
      expect(next.wallpaperEnabled, isFalse);

      await next.saveWallpaperEnabled(true);
      expect(next.wallpaperEnabled, isTrue);
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(SettingsStore.wallpaperEnabledKey), isFalse);
    });

    test('壁纸 API 自定义地址持久化，空值/默认值回落', () async {
      final SettingsStore store = SettingsStore();
      await store.init();

      await store.saveWallpaperApiUrl('https://example.com/wallpaper');
      expect(store.wallpaperApiUrl, 'https://example.com/wallpaper');

      final SettingsStore next = SettingsStore();
      await next.init();
      expect(next.wallpaperApiUrl, 'https://example.com/wallpaper');

      await next.saveWallpaperApiUrl('   ');
      expect(next.wallpaperApiUrl, SettingsStore.defaultWallpaperApiUrl);
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(SettingsStore.wallpaperApiUrlKey), isFalse);

      await next.saveWallpaperApiUrl(SettingsStore.defaultWallpaperApiUrl);
      expect(prefs.containsKey(SettingsStore.wallpaperApiUrlKey), isFalse);
    });

    test('壁纸刷新间隔持久化，默认值删除键，非法值回落', () async {
      final SettingsStore store = SettingsStore();
      await store.init();
      expect(store.wallpaperMinutes, SettingsStore.defaultWallpaperMinutes);

      await store.saveWallpaperMinutes(60);
      expect(store.wallpaperMinutes, 60);

      final SettingsStore next = SettingsStore();
      await next.init();
      expect(next.wallpaperMinutes, 60);

      await next.saveWallpaperMinutes(SettingsStore.defaultWallpaperMinutes);
      expect(next.wallpaperMinutes, SettingsStore.defaultWallpaperMinutes);
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(SettingsStore.wallpaperMinutesKey), isFalse);

      await next.saveWallpaperMinutes(7);
      expect(next.wallpaperMinutes, SettingsStore.defaultWallpaperMinutes);
    });

    test('壁纸间隔标签', () {
      expect(SettingsStore.wallpaperMinuteLabel(5), '5 分钟');
      expect(SettingsStore.wallpaperMinuteLabel(60), '60 分钟');
      expect(SettingsStore.wallpaperMinuteLabel(720), '半天');
      expect(SettingsStore.wallpaperMinuteLabel(1440), '1 天');
    });
  });
}
