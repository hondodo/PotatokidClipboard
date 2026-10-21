import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_screen/app/config/screen_assets.dart';

void main() {
  group('ScreenAssets', () {
    setUp(() => ScreenAssets.configure(root: ''));
    tearDown(() => ScreenAssets.configure(root: ''));

    test('默认根路径为空，path 直接拼接相对路径', () {
      expect(ScreenAssets.path('assets/datas/tv_name_order.txt'),
          'assets/datas/tv_name_order.txt');
    });

    test('宿主可改写根路径以命中依赖包前缀', () {
      ScreenAssets.configure(root: 'packages/pscreen_screen/');
      expect(ScreenAssets.path('assets/datas/tv_name_order.txt'),
          'packages/pscreen_screen/assets/datas/tv_name_order.txt');
    });

    test('configure 归一化：去掉尾部斜杠、补上头部斜杠', () {
      ScreenAssets.configure(root: 'packages/pscreen_screen');
      expect(ScreenAssets.root, 'packages/pscreen_screen/');
      ScreenAssets.configure(root: '/assets');
      expect(ScreenAssets.root, 'assets/');
    });
  });
}
