import 'package:flutter_test/flutter_test.dart';
import 'package:potatokid_screen/features/iptv/domain/channel_name_normalizer.dart';

void main() {
  group('前缀补连字符', () {
    test('CCTV 缺连字符的写法统一成 CCTV-', () {
      expect(normalizeChannelName('CCTV1'), 'CCTV-1');
      expect(normalizeChannelName('CCTV2'), 'CCTV-2');
      expect(normalizeChannelName('CCTV17'), 'CCTV-17');
      expect(normalizeChannelName('CCTV4K'), 'CCTV-4K');
      expect(normalizeChannelName('CCTV5+'), 'CCTV-5+');
      expect(normalizeChannelName('CETV01'), 'CETV-01');
    });

    test('大小写不敏感，输出统一大写前缀', () {
      expect(normalizeChannelName('cctv1'), 'CCTV-1');
      expect(normalizeChannelName('Cctv5+'), 'CCTV-5+');
      expect(normalizeChannelName('cetv01'), 'CETV-01');
    });

    test('前缀与数字之间的空白也一并去掉', () {
      expect(normalizeChannelName('CCTV 1'), 'CCTV-1');
      expect(normalizeChannelName('CCTV  4 欧洲'), 'CCTV-4 欧洲');
    });

    test('幂等：已经带连字符的不再变化', () {
      expect(normalizeChannelName('CCTV-1'), 'CCTV-1');
      expect(normalizeChannelName(normalizeChannelName('CCTV1')), 'CCTV-1');
      expect(normalizeChannelName('CCTV-5+'), 'CCTV-5+');
    });

    test('带后缀的版本保持独立，不会被并成同一个台', () {
      expect(normalizeChannelName('CCTV-4 欧洲'), 'CCTV-4 欧洲');
      expect(normalizeChannelName('CCTV4K真4K'), 'CCTV-4K真4K');
      expect(normalizeChannelName('CCTV-4 欧洲'), isNot(normalizeChannelName('CCTV4')));
    });

    test('非白名单前缀与普通频道名原样返回', () {
      expect(normalizeChannelName('咪咕赛事播40'), '咪咕赛事播40');
      expect(normalizeChannelName('凤凰资讯'), '凤凰资讯');
      expect(normalizeChannelName('CGTN英语'), 'CGTN英语');
      expect(normalizeChannelName('HBO2'), 'HBO2');
      expect(normalizeChannelName('CCTV'), 'CCTV');
      expect(normalizeChannelName(''), '');
      expect(normalizeChannelName('  CCTV1  '), 'CCTV-1');
    });
  });
}
