import 'package:pscreen_screen/features/iptv/application/channel_list_cache.dart';
import 'package:pscreen_screen/features/iptv/data/datasources/remote/final_channels_service.dart';
import 'package:pscreen_screen/features/iptv/domain/models/final_channels.dart';
import 'package:pscreen_screen/features/iptv/domain/repositories/iptv_repository.dart';

/// IPTV 仓库实现：拉取服务端已合并好的最终频道列表，并把新版本写回本地缓存。
///
/// 合并 / 隐藏 / 排序 / 强制移除源都在服务端完成，客户端不再自行合成。
/// 网络异常自然向上冒泡，由 BLoC 统一捕获并转为 State。
class IptvRepositoryImpl implements IptvRepository {
  IptvRepositoryImpl({
    FinalChannelsService? service,
    ChannelListCache? cache,
  })  : _service = service ?? FinalChannelsService(),
        _cache = cache ?? ChannelListCache.instance;

  final FinalChannelsService _service;
  final ChannelListCache _cache;

  @override
  Future<FinalChannelsPayload?> fetchFinalChannels({String? version}) async {
    final FinalChannelsFetchResult result =
        await _service.fetch(version: version);
    final FinalChannelsPayload? payload = result.payload;
    if (payload != null) {
      await _cache.save(payload);
    }
    return payload;
  }
}
