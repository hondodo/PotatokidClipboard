import 'package:flutter_test/flutter_test.dart';
import 'package:potatokid_screen/features/iptv/domain/channel_name_matcher.dart';

void main() {
  group('ChannelNameMatcher 精确全等', () {
    final ChannelNameMatcher m = ChannelNameMatcher(<String>[
      'CCTV-5',
      '滁州市广播电视台 新闻综合',
    ]);

    test('完全相同的名字命中', () {
      expect(m.matches('CCTV-5'), isTrue);
      expect(m.matches('滁州市广播电视台 新闻综合'), isTrue);
    });

    test('精确行大小写敏感、空格要原样', () {
      expect(m.matches('cctv-5'), isFalse);
      expect(m.matches('CCTV-5+'), isFalse);
      expect(m.matches('滁州市广播电视台  新闻综合'), isFalse);
    });
  });

  group('ChannelNameMatcher 星号通配', () {
    test('两侧 * = 包含', () {
      final ChannelNameMatcher m = ChannelNameMatcher(<String>['*咪咕*']);
      expect(m.matches('咪咕赛事播40'), isTrue);
      expect(m.matches('CCTV-5'), isFalse);
    });

    test('前缀 * 只匹配开头，后缀 * 只匹配结尾', () {
      expect(ChannelNameMatcher(<String>['咪咕*']).matches('咪咕赛事播40'), isTrue);
      expect(ChannelNameMatcher(<String>['咪咕*']).matches('看咪咕'), isFalse);
      expect(ChannelNameMatcher(<String>['*咪咕']).matches('看咪咕'), isTrue);
      expect(ChannelNameMatcher(<String>['*咪咕']).matches('咪咕赛事'), isFalse);
    });

    test('通配忽略大小写', () {
      expect(ChannelNameMatcher(<String>['*NewTv*']).matches('NewTV惊悚悬疑'), isTrue);
      expect(ChannelNameMatcher(<String>['*ihot*']).matches('iHot直播'), isTrue);
    });

    test('多段需按顺序出现，且首段锚定开头', () {
      final ChannelNameMatcher m = ChannelNameMatcher(<String>['a*b*c']);
      expect(m.matches('abc'), isTrue);
      expect(m.matches('aXbYc'), isTrue);
      expect(m.matches('acb'), isFalse);
      expect(m.matches('xabc'), isFalse);
    });

    test('末段锚定结尾时，取贴在结尾的那次出现', () {
      // `*ab` 对 `abab`：中间那次不算，结尾那次才算。
      expect(ChannelNameMatcher(<String>['*ab']).matches('abab'), isTrue);
      expect(ChannelNameMatcher(<String>['*ab']).matches('abac'), isFalse);
    });

    test('只由 * 组成的模式视为无效，不会隐藏整个列表', () {
      expect(ChannelNameMatcher(<String>['*', '**']).isEmpty, isTrue);
      expect(ChannelNameMatcher(<String>['*']).matches('任何频道'), isFalse);
    });
  });

  test('空规则与空名字都不命中', () {
    expect(ChannelNameMatcher(const <String>[]).matches('CCTV-1'), isFalse);
    expect(ChannelNameMatcher(<String>['*咪咕*']).matches(''), isFalse);
  });

  group('与频道名归一化配合（CCTV1 / CCTV-1 视作同一个台）', () {
    test('精确条目两种写法都能命中', () {
      expect(ChannelNameMatcher(<String>['CCTV-1']).matches('CCTV1'), isTrue);
      expect(ChannelNameMatcher(<String>['CCTV1']).matches('CCTV-1'), isTrue);
      expect(ChannelNameMatcher(<String>['CCTV-1']).matches('CCTV-2'), isFalse);
    });

    test('通配条目的片段同样被归一化', () {
      expect(ChannelNameMatcher(<String>['*CCTV1*']).matches('CCTV-1'), isTrue);
      expect(ChannelNameMatcher(<String>['*CCTV-1*']).matches('CCTV1'), isTrue);
      // `*CCTV*` 对两种写法都命中。
      expect(ChannelNameMatcher(<String>['*CCTV*']).matches('CCTV1'), isTrue);
      expect(ChannelNameMatcher(<String>['*CCTV*']).matches('CCTV-5+'), isTrue);
    });
  });
}
