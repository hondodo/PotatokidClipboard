import 'package:flutter/services.dart' show rootBundle;
import 'package:potatokid_screen/features/iptv/data/datasources/remote/iptv_m3u_parser.dart';
import 'package:potatokid_screen/features/iptv/domain/models/iptv_channel.dart';

/// 包内 m3u 资源数据源。
///
/// - [collectPath]：自建精选频道，**始终拼接在最终列表最前**，且不写入持久化缓存；
/// - [defaultApiPath]：接口不可用且无持久化缓存时的默认列表快照（打包时的接口结果）。
class IptvAssetSource {
  /// 自建精选频道列表（始终置顶）。
  static const String collectPath = 'assets/datas/collect.m3u';

  /// 接口不可用时的默认频道列表快照。
  static const String defaultApiPath = 'assets/datas/guovin-api.m3u';

  /// 读取自建精选频道列表。
  Future<List<IptvChannel>> loadCollect() => loadFromAsset(collectPath);

  /// 读取接口默认快照列表。
  Future<List<IptvChannel>> loadDefaultApi() => loadFromAsset(defaultApiPath);

  /// 读取并解析指定 m3u 资源；资源缺失/解析异常返回空列表，不阻断主流程。
  Future<List<IptvChannel>> loadFromAsset(String path) async {
    try {
      return IptvM3uParser.parse(await rootBundle.loadString(path));
    } catch (_) {
      return const <IptvChannel>[];
    }
  }
}