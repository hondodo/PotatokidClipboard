import 'package:potatokid_screen/app/config/data_files.dart';
import 'package:potatokid_screen/features/iptv/data/datasources/remote/iptv_m3u_parser.dart';
import 'package:potatokid_screen/features/iptv/domain/models/iptv_channel.dart';

/// 包内 m3u 资源数据源。内容由 [DataFiles] 提供（git 同步结果 → 本地缓存 →
/// 包内 `assets/datas` 默认值），所以这些列表都**不发新版也能更新**。
///
/// - `collect.m3u`：自建精选频道，**始终拼接在最终列表最前**，且不写入持久化缓存；
/// - `guovin-api.m3u`：接口不可用且无持久化缓存时的默认列表快照（打包时的接口结果）；
/// - `audio.m3u`：广播电台（纯音频源），**始终拼接在最终列表最后**。
class IptvAssetSource {
  /// 读取自建精选频道列表。
  Future<List<IptvChannel>> loadCollect() => _load(DataFiles.idCollect);

  /// 读取接口默认快照列表。
  Future<List<IptvChannel>> loadDefaultApi() => _load(DataFiles.idGuovinApi);

  /// 读取广播电台列表（纯音频，拼在列表末尾）。
  Future<List<IptvChannel>> loadAudio() => _load(DataFiles.idAudio);

  /// 读取并解析指定数据文件；内容缺失/解析异常返回空列表，不阻断主流程。
  ///
  /// 内容已在内存里（[DataFiles] 加载过），所以这里没有磁盘/资源 IO。
  Future<List<IptvChannel>> _load(String id) async {
    try {
      await DataFiles.instance.loadLocal();
      return IptvM3uParser.parse(DataFiles.instance.text(id));
    } catch (_) {
      return const <IptvChannel>[];
    }
  }
}