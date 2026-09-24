import 'package:dio/dio.dart';
import 'package:potatokid_screen/app/config/app_constants.dart';
import 'package:potatokid_screen/core/network/dio_manager.dart';
import 'package:potatokid_screen/features/iptv/data/datasources/remote/iptv_m3u_parser.dart';
import 'package:potatokid_screen/features/iptv/domain/models/iptv_channel.dart';

/// IPTV 数据源：拉取远程 m3u 播放列表并解析为频道列表。
/// 复用 [DioManager]（连通性检查 + 重试），原始文本交由 [IptvM3uParser] 解析。
class IptvApiService {
  /// 拉取并解析默认直播列表中所有频道。
  Future<List<IptvChannel>> fetchChannels() async {
    final dynamic data = await DioManager().send(
      url: AppConstants.iptvM3uUrl,
      responseType: ResponseType.plain,
      notTipNetError: true,
    );
    return IptvM3uParser.parse(data is String ? data : '');
  }
}