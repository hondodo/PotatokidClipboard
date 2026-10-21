import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_screen/app/config/screen_assets.dart';

void main() {
  group('ScreenAssets', () {
    setUp(() => ScreenAssets.configure(root: ''));

    test('默认根路径为空，path 直接拼接相对路径', () {
      expect(ScreenAssets.path('assets/datas/tv_name_order.txt'),
          'assets/datas/tv_name_order.txt');
    });

    test('宿主可改写根路径以命中依赖包前缀', () {
      ScreenAssets.configure(root: 'packages/pscreen_screen/');
      expect(ScreenAssets.path('assets/datas/tv_name_order.txt'),
          'packages/pscreen_screen/assets/datas/tv_name_order.txt');
    });

    test('configure 归一化：去掉首尾斜杠并补上尾部斜杠', () {
      ScreenAssets.configure(root: 'packages/pscreen_screen');
      expect(ScreenAssets.root, 'packages/pscreen_screen/');
      ScreenAssets.configure(root: '/assets');
      expect(ScreenAssets.root, 'assets/');
    });

    test('configure 归一化边界输入', () {
      const Map<String, String> cases = <String, String>{
        '': '',
        '/': '',
        '///': '',
        '   ': '',
        'packages/x': 'packages/x/',
        'packages/x/': 'packages/x/',
        'packages/x///': 'packages/x/',
        '/packages/x/': 'packages/x/',
        '  packages/x  ': 'packages/x/',
      };
      cases.forEach((String input, String expected) {
        ScreenAssets.configure(root: input);
        expect(ScreenAssets.root, expected, reason: 'input: "$input"');
      });
    });

    test('path 去掉 relative 的前导斜杠，不产生双斜杠', () {
      ScreenAssets.configure(root: 'packages/pscreen_screen');
      expect(ScreenAssets.path('/assets/datas/x.txt'),
          'packages/pscreen_screen/assets/datas/x.txt');
    });

    test('isConfigured 反映是否已配置', () {
      expect(ScreenAssets.isConfigured, isFalse);
      ScreenAssets.configure(root: 'packages/pscreen_screen/');
      expect(ScreenAssets.isConfigured, isTrue);
    });

    test('requireConfigured 未配置时抛出 StateError', () {
      expect(() => ScreenAssets.requireConfigured(), throwsStateError);
      ScreenAssets.configure(root: 'packages/pscreen_screen/');
      expect(() => ScreenAssets.requireConfigured(), returnsNormally);
    });
  });
}
