import 'package:potatokid_screen/app/config/app_config.dart';
import 'package:potatokid_screen/features/iptv/data/datasources/local/iptv_asset_source.dart';
import 'package:potatokid_screen/features/iptv/data/datasources/remote/iptv_api_service.dart';
import 'package:potatokid_screen/features/iptv/domain/channel_name_matcher.dart';
import 'package:potatokid_screen/features/iptv/domain/channel_name_normalizer.dart';
import 'package:potatokid_screen/features/iptv/domain/models/iptv_channel.dart';
import 'package:potatokid_screen/features/iptv/domain/repositories/iptv_repository.dart';

/// IPTV 仓库实现：负责「接口数据 → 最终播放列表」的合成。
///
/// 最终列表 = `collect.m3u`（置顶）+ 接口数据（或缓存/默认快照）+ `audio.m3u`
/// （广播电台收尾），先把频道名归一化（`CCTV1` → `CCTV-1`）再同名合并，
/// 然后按 TV_NAME_ORDER 提权、剔除 TV_NAME_HIDE（精确全等 + `*` 通配）。
/// 这些配置与 m3u 都由 DataFiles 提供，可随 git 同步更新，
/// 因此不做「只读一次」的内存常驻。
/// 网络异常自然向上冒泡，由 BLoC 统一捕获并转为 State。
class IptvRepositoryImpl implements IptvRepository {
  IptvRepositoryImpl({IptvApiService? api, IptvAssetSource? assets})
      : _api = api ?? IptvApiService(),
        _assets = assets ?? IptvAssetSource();

  final IptvApiService _api;
  final IptvAssetSource _assets;

  @override
  Future<List<IptvChannel>> fetchRemoteChannels() => _api.fetchChannels();

  @override
  Future<List<IptvChannel>> loadDefaultRemoteChannels() =>
      _assets.loadDefaultApi();

  @override
  Future<List<IptvChannel>> buildPlaylist(List<IptvChannel> remote) async {
    // 两者都只是读内存里的文本再解析，顺序 await 即可。
    final List<IptvChannel> collect = await _assets.loadCollect();
    final List<IptvChannel> audio = await _assets.loadAudio();
    return _compose(collect: collect, remote: remote, audio: audio);
  }

  /// collect 前置 + remote + audio 收尾，同名合并源（collect 的源在最前），
  /// 再剔除 TV_NAME_HIDE、按 TV_NAME_ORDER 置顶。
  static List<IptvChannel> _compose({
    required List<IptvChannel> collect,
    required List<IptvChannel> remote,
    required List<IptvChannel> audio,
  }) {
    // 1) 先统一频道名写法（`CCTV1` → `CCTV-1`）再按名称合并：
    //    否则同一个台会各占一个位置（各带一部分源），
    //    且 `CCTV-1` 的顺序 / 隐藏规则匹配不上接口给的 `CCTV1`。
    final Map<String, IptvChannel> byName = <String, IptvChannel>{};
    for (final IptvChannel raw in <IptvChannel>[...collect, ...remote, ...audio]) {
      final IptvChannel channel = _normalizedName(raw);
      final IptvChannel? exist = byName[channel.name];
      byName[channel.name] =
          exist == null ? channel : _mergeSameName(exist, channel);
    }
    final List<IptvChannel> merged = byName.values.toList(growable: false);

    // 2) 剔除需要隐藏的频道（精确全等 + `*` 通配，见 [ChannelNameMatcher]）。
    final ChannelNameMatcher hide = ChannelNameMatcher(AppConfig.tvNameHide);
    final List<IptvChannel> visible = merged
        .where((IptvChannel c) => !hide.matches(c.name))
        .toList(growable: false);

    // 3) TV_NAME_ORDER 中列出的频道按配置顺序置顶（列表里不存在的忽略）。
    //    条目也做同样的归一化，所以规则文件里写 `CCTV1` 还是 `CCTV-1` 都能命中。
    final List<IptvChannel> head = <IptvChannel>[];
    final Set<String> used = <String>{};
    for (final String raw in AppConfig.tvNameOrder) {
      final String name = normalizeChannelName(raw);
      if (!used.add(name)) continue;
      final int index = visible.indexWhere((IptvChannel c) => c.name == name);
      if (index >= 0) head.add(visible[index]);
    }
    if (head.isEmpty) return visible;

    final Set<String> headNames =
        head.map((IptvChannel c) => c.name).toSet();
    return <IptvChannel>[
      ...head,
      ...visible.where((IptvChannel c) => !headNames.contains(c.name)),
    ];
  }

  /// 名字写法统一（`CCTV1` → `CCTV-1`）；本来就统一的直接复用，避免多余分配。
  static IptvChannel _normalizedName(IptvChannel channel) {
    final String name = normalizeChannelName(channel.name);
    if (name == channel.name) return channel;
    return IptvChannel(
      name: name,
      sources: channel.sources,
      logo: channel.logo,
      group: channel.group,
    );
  }

  /// 同名合并：源按出现顺序去重拼接（[first] 的源在前），台标/分组取首个非空。
  static IptvChannel _mergeSameName(IptvChannel first, IptvChannel second) {
    final List<String> sources = <String>[...first.sources];
    for (final String url in second.sources) {
      if (!sources.contains(url)) sources.add(url);
    }
    return IptvChannel(
      name: first.name,
      sources: sources,
      logo: first.logo ?? second.logo,
      group: first.group ?? second.group,
    );
  }
}