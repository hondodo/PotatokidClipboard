import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_screen/core/parental/parental_config.dart';
import 'package:pscreen_screen/features/iptv/application/bloc/iptv_bloc.dart';
import 'package:pscreen_screen/features/iptv/domain/models/iptv_channel.dart';

/// 儿童模式两档过滤（`IptvBloc.applyParentalFilter`，注入 `_viewOf` 末尾）：
/// strict = allowGroups ∩ allowChannels（命中分组且命中频道名）；
/// mild = hideGroups ∪ hideChannels 并集隐藏；空值不限制；
/// 多档案 = 每个选中档案都放行；结果为空 → 不应用（防黑屏）。
void main() {
  const List<IptvChannel> channels = <IptvChannel>[
    IptvChannel(name: 'CCTV-1', group: '央视频道', sources: <String>['a']),
    IptvChannel(name: 'CCTV-5', group: '央视频道', sources: <String>['b']),
    IptvChannel(name: '湖南卫视', group: '卫视频道', sources: <String>['c']),
    IptvChannel(name: '凤凰资讯', group: '境外频道', sources: <String>['d']),
    IptvChannel(name: '本地新闻', group: null, sources: <String>['e']),
  ];

  ChildProfile strictProfile({
    List<String> allowGroups = const <String>[],
    List<String> allowChannels = const <String>[],
  }) =>
      ChildProfile(
        id: 's1',
        name: '严格娃',
        profileMode: 'strict',
        allowGroups: allowGroups,
        allowChannels: allowChannels,
      );

  ChildProfile mildProfile({
    List<String> hideGroups = const <String>[],
    List<String> hideChannels = const <String>[],
  }) =>
      ChildProfile(
        id: 'm1',
        name: '温和娃',
        profileMode: 'mild',
        hideGroups: hideGroups,
        hideChannels: hideChannels,
      );

  ParentalConfig configWith(List<ChildProfile> children) =>
      ParentalConfig(mode: 'on', children: children);

  List<String> namesOf(List<IptvChannel> list) =>
      list.map((IptvChannel c) => c.name).toList(growable: false);

  group('strict 加法白名单（分组 ∩ 频道名）', () {
    test('命中分组且命中频道名 → 保留，其余剔除', () {
      final List<IptvChannel> out = IptvBloc.applyParentalFilter(
        channels,
        config: configWith(<ChildProfile>[
          strictProfile(
            allowGroups: const <String>['央视频道'],
            allowChannels: const <String>['CCTV-*'],
          ),
        ]),
        profiles: <ChildProfile>[
          strictProfile(
            allowGroups: const <String>['央视频道'],
            allowChannels: const <String>['CCTV-*'],
          ),
        ],
      );
      expect(namesOf(out), <String>['CCTV-1', 'CCTV-5']);
    });

    test('分组命中但频道名不命中 → 剔除（两维度取交集）', () {
      final ChildProfile profile = strictProfile(
        allowGroups: const <String>['央视频道'],
        allowChannels: const <String>['CCTV-1'],
      );
      final List<IptvChannel> out = IptvBloc.applyParentalFilter(
        channels,
        config: configWith(<ChildProfile>[profile]),
        profiles: <ChildProfile>[profile],
      );
      expect(namesOf(out), <String>['CCTV-1']);
    });

    test('频道名命中但分组不命中 → 剔除（两维度取交集）', () {
      final ChildProfile profile = strictProfile(
        allowGroups: const <String>['卫视频道'],
        allowChannels: const <String>['CCTV-1', '湖南卫视'],
      );
      final List<IptvChannel> out = IptvBloc.applyParentalFilter(
        channels,
        config: configWith(<ChildProfile>[profile]),
        profiles: <ChildProfile>[profile],
      );
      // CCTV-1 频道名命中但分组不在白名单 → 剔除；仅湖南卫视两维度全中。
      expect(namesOf(out), <String>['湖南卫视']);
    });

    test('无分组频道不命中任何 allowGroups → 剔除', () {
      final ChildProfile profile = strictProfile(
        allowGroups: const <String>['央视频道'],
      );
      final List<IptvChannel> out = IptvBloc.applyParentalFilter(
        channels,
        config: configWith(<ChildProfile>[profile]),
        profiles: <ChildProfile>[profile],
      );
      expect(namesOf(out), <String>['CCTV-1', 'CCTV-5']);
    });

    test('两个白名单字段都为空 = 不限制 → 全部保留', () {
      final ChildProfile profile = strictProfile();
      final List<IptvChannel> out = IptvBloc.applyParentalFilter(
        channels,
        config: configWith(<ChildProfile>[profile]),
        profiles: <ChildProfile>[profile],
      );
      expect(out, hasLength(channels.length));
    });
  });

  group('mild 减法黑名单（分组 ∪ 频道名并集隐藏）', () {
    test('hideGroups 命中分组 → 整组隐藏', () {
      final ChildProfile profile =
          mildProfile(hideGroups: const <String>['央视频道']);
      final List<IptvChannel> out = IptvBloc.applyParentalFilter(
        channels,
        config: configWith(<ChildProfile>[profile]),
        profiles: <ChildProfile>[profile],
      );
      expect(namesOf(out),
          <String>['湖南卫视', '凤凰资讯', '本地新闻']);
    });

    test('hideChannels 命中频道名（含通配）→ 单台隐藏', () {
      final ChildProfile profile =
          mildProfile(hideChannels: const <String>['*资讯*']);
      final List<IptvChannel> out = IptvBloc.applyParentalFilter(
        channels,
        config: configWith(<ChildProfile>[profile]),
        profiles: <ChildProfile>[profile],
      );
      expect(namesOf(out),
          <String>['CCTV-1', 'CCTV-5', '湖南卫视', '本地新闻']);
    });

    test('分组与频道两个黑名单取并集', () {
      final ChildProfile profile = mildProfile(
        hideGroups: const <String>['卫视频道'],
        hideChannels: const <String>['CCTV-5'],
      );
      final List<IptvChannel> out = IptvBloc.applyParentalFilter(
        channels,
        config: configWith(<ChildProfile>[profile]),
        profiles: <ChildProfile>[profile],
      );
      expect(namesOf(out), <String>['CCTV-1', '凤凰资讯', '本地新闻']);
    });

    test('两个黑名单字段都为空 = 不限制 → 全部保留', () {
      final ChildProfile profile = mildProfile();
      final List<IptvChannel> out = IptvBloc.applyParentalFilter(
        channels,
        config: configWith(<ChildProfile>[profile]),
        profiles: <ChildProfile>[profile],
      );
      expect(out, hasLength(channels.length));
    });
  });

  group('多档案合并与防黑屏', () {
    test('每个选中档案都放行才展示（mild ∩ strict 取最严）', () {
      final ChildProfile mild = mildProfile(
        hideChannels: const <String>['CCTV-5'],
      );
      final ChildProfile strict = strictProfile(
        allowGroups: const <String>['央视频道', '卫视频道', '境外频道'],
      );
      final List<IptvChannel> out = IptvBloc.applyParentalFilter(
        channels,
        config: configWith(<ChildProfile>[mild, strict]),
        profiles: <ChildProfile>[mild, strict],
      );
      // strict 先收窄到有分组的四台，mild 再剔掉 CCTV-5。
      expect(namesOf(out),
          <String>['CCTV-1', '湖南卫视', '凤凰资讯']);
    });

    test('白名单结果为空 → 不应用并返回原列表（防黑屏）', () {
      final ChildProfile profile = strictProfile(
        allowGroups: const <String>['不存在的分组'],
      );
      final List<IptvChannel> out = IptvBloc.applyParentalFilter(
        channels,
        config: configWith(<ChildProfile>[profile]),
        profiles: <ChildProfile>[profile],
      );
      expect(identical(out, channels) || out.length == channels.length, isTrue);
      expect(namesOf(out), namesOf(channels));
    });

    test('黑名单命中全部频道 → 同样不应用（防黑屏）', () {
      final ChildProfile profile =
          mildProfile(hideChannels: const <String>['*']);
      final List<IptvChannel> out = IptvBloc.applyParentalFilter(
        channels,
        config: configWith(<ChildProfile>[profile]),
        profiles: <ChildProfile>[profile],
      );
      // 纯 `*` 模式被 ChannelNameMatcher 视为无效忽略 → 实际不隐藏；
      // 换成会全命中的具体黑名单验证兜底。
      expect(out, isNotEmpty);

      final ChildProfile all = mildProfile(
        hideGroups: const <String>[
          '央视频道',
          '卫视频道',
          '境外频道',
        ],
        hideChannels: const <String>['本地新闻'],
      );
      final List<IptvChannel> out2 = IptvBloc.applyParentalFilter(
        channels,
        config: configWith(<ChildProfile>[all]),
        profiles: <ChildProfile>[all],
      );
      expect(namesOf(out2), namesOf(channels));
    });

    test('判定式不成立（mode=off）或未选档案 → 原样返回', () {
      final ChildProfile profile =
          mildProfile(hideChannels: const <String>['*']);
      final ParentalConfig off = const ParentalConfig(
        mode: 'off',
        children: <ChildProfile>[],
      );
      // mode=off：即使 children 传了也不过滤（enabled 为 false）。
      expect(
        identical(
          IptvBloc.applyParentalFilter(channels,
              config: off, profiles: <ChildProfile>[profile]),
          channels,
        ),
        isTrue,
      );
      // 未选档案（profiles 为空）不过滤。
      expect(
        identical(
          IptvBloc.applyParentalFilter(channels,
              config: configWith(<ChildProfile>[profile]),
              profiles: const <ChildProfile>[]),
          channels,
        ),
        isTrue,
      );
    });
  });
}
