import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/core/storage/settings_store.dart';
import 'package:pscreen_home/core/wallpaper/wallpaper_controller.dart';

class _FakeSettingsStore extends SettingsStore {
  bool enabled = SettingsStore.defaultWallpaperEnabled;
  String apiUrl = SettingsStore.defaultWallpaperApiUrl;
  int minutes = SettingsStore.defaultWallpaperMinutes;

  @override
  bool get wallpaperEnabled => enabled;

  @override
  String get wallpaperApiUrl => apiUrl;

  @override
  int get wallpaperMinutes => minutes;

  @override
  Future<void> saveWallpaperEnabled(bool value) async {
    enabled = value;
  }

  @override
  Future<void> saveWallpaperApiUrl(String url) async {
    apiUrl = url.trim().isEmpty
        ? SettingsStore.defaultWallpaperApiUrl
        : url.trim();
  }

  @override
  Future<void> saveWallpaperMinutes(int value) async {
    if (!SettingsStore.wallpaperMinuteOptions.contains(value)) return;
    minutes = value;
  }
}

void main() {
  group('WallpaperController', () {
    test('从存储读取默认配置', () {
      final WallpaperController controller = WallpaperController(
        _FakeSettingsStore(),
      );

      expect(controller.enabled, isTrue);
      expect(controller.apiUrl, SettingsStore.defaultWallpaperApiUrl);
      expect(controller.minutes, 30);
    });

    test('开关/API/间隔更新会通知并持久化', () async {
      final _FakeSettingsStore store = _FakeSettingsStore();
      final WallpaperController controller = WallpaperController(store);
      int notifications = 0;
      controller.addListener(() => notifications++);

      await controller.setEnabled(false);
      expect(controller.enabled, isFalse);
      expect(store.enabled, isFalse);
      expect(notifications, 1);

      await controller.setApiUrl('https://example.com/wallpaper');
      expect(controller.apiUrl, 'https://example.com/wallpaper');
      expect(store.apiUrl, 'https://example.com/wallpaper');
      expect(notifications, 2);

      await controller.setMinutes(720);
      expect(controller.minutes, 720);
      expect(store.minutes, 720);
      expect(notifications, 3);

      // 相同值 / 非法间隔不通知。
      await controller.setMinutes(720);
      await controller.setMinutes(7);
      expect(notifications, 3);
    });

    test('空白 API 回落默认风景接口', () async {
      final _FakeSettingsStore store = _FakeSettingsStore();
      final WallpaperController controller = WallpaperController(store);

      await controller.setApiUrl('   ');

      expect(controller.apiUrl, SettingsStore.defaultWallpaperApiUrl);
      expect(store.apiUrl, SettingsStore.defaultWallpaperApiUrl);
    });

    test('每次换图都会生成唯一的缓存破坏地址', () {
      final WallpaperController controller = WallpaperController(
        _FakeSettingsStore(),
      );

      final String first = controller.nextImageUrl();
      final String second = controller.nextImageUrl();

      expect(first, startsWith(SettingsStore.defaultWallpaperApiUrl));
      expect(first, contains('_t='));
      expect(second, isNot(first));
      expect(second, startsWith(SettingsStore.defaultWallpaperApiUrl));
    });

    test('自定义 API 会保留原有查询参数并追加缓存破坏参数', () {
      final _FakeSettingsStore store = _FakeSettingsStore()
        ..apiUrl = 'https://uapis.cn/api/v1/random/image?category=landscape';
      final WallpaperController controller = WallpaperController(store);

      final String url = controller.nextImageUrl();

      expect(url, contains('category=landscape'));
      expect(url, contains('_t='));
    });

    test('非法 API 回落默认地址并仍带缓存破坏参数', () {
      final _FakeSettingsStore store = _FakeSettingsStore()
        ..apiUrl = 'not a url';
      final WallpaperController controller = WallpaperController(store);

      final String url = controller.nextImageUrl();

      expect(url, startsWith(SettingsStore.defaultWallpaperApiUrl));
      expect(url, contains('_t='));
    });
  });
}
