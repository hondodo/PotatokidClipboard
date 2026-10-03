import 'package:dio/dio.dart';
import 'package:potatokid_screen/app/config/app_constants.dart';
import 'package:potatokid_screen/core/network/dio_manager.dart';
import 'package:potatokid_screen/core/network/net_exceptions.dart';
import 'package:potatokid_screen/core/network/raw_content_url_resolver.dart';
import 'package:potatokid_screen/features/iptv/data/datasources/remote/iptv_m3u_parser.dart';
import 'package:potatokid_screen/features/iptv/domain/models/iptv_channel.dart';

/// IPTV 数据源：拉取远程 m3u 播放列表并解析为频道列表。
///
/// 地址是**两跳**的：先请求 [AppConstants.iptvM3uUrl]，拿到的是一个指向真正
/// 播放列表的第三方链接（纯文本，可能带空行/注释）；再请求该链接才是 m3u 内容。
/// 复用 [DioManager]（连通性检查 + 重试），原始文本交由 [IptvM3uParser] 解析。
/// 两跳的地址都会先经 [RawContentUrlResolver] 还原成原始文件地址（GitHub
/// `blob` 文件页是 HTML，必须换成 raw 直链），再对 GitHub 地址套加速前缀，
/// 见 [_getPlain] 与 [_withGithubProxy]。
class IptvApiService {
  /// 拉取并解析远程频道列表。
  Future<List<IptvChannel>> fetchChannels() async {
    return IptvM3uParser.parse(await fetchPlaylistText());
  }

  /// 拉取真正的 m3u 文本（两跳）。
  ///
  /// 容错：第一跳若直接返回 m3u 正文（含 `#EXTINF`），则不再请求第二跳；
  /// 既不是链接也不是 m3u 时抛出 [HttpCodeException]，由上层走缓存/包内兜底。
  Future<String> fetchPlaylistText() async {
    final String first = await _getPlain(AppConstants.iptvM3uUrl);
    final String target = _firstUrl(first);
    if (target.isEmpty) {
      if (first.contains('#EXTINF')) return first;
      throw const HttpCodeException(200, '第一跳未返回播放列表地址');
    }
    return _getPlain(target);
  }

  Future<String> _getPlain(String url) async {
    final dynamic data = await DioManager().send(
      // 先还原原始文件地址（GitHub `blob` 文件页返回的是 HTML，拿不到正文），
      // 再套加速前缀；两步顺序不能反，前缀必须作用在最终的 raw 地址上。
      url: _withGithubProxy(RawContentUrlResolver.resolve(url)),
      responseType: ResponseType.plain,
      notTipNetError: true,
    );
    return data is String ? data : '';
  }

  /// GitHub 直链套加速前缀，其余域名原样返回。
  ///
  /// 第二跳拿到的常是 GitHub release 下载地址，国内直连会在连接阶段超时；
  /// 前缀由 [AppConstants.githubProxyPrefix] 配置，为空则不改写。
  static String _withGithubProxy(String url) {
    final String prefix = AppConstants.githubProxyPrefix;
    if (prefix.isEmpty || url.startsWith(prefix)) return url;
    final Uri? uri = Uri.tryParse(url);
    if (uri == null) return url;
    final String host = uri.host.toLowerCase();
    final bool isGithub = host == 'github.com' ||
        host.endsWith('.github.com') ||
        host == 'githubusercontent.com' ||
        host.endsWith('.githubusercontent.com');
    return isGithub ? '$prefix$url' : url;
  }

  /// 取文本中第一个 http(s) 链接行（跳过 BOM/空行/注释）。
  static String _firstUrl(String text) {
    for (final String line in text.split('\n')) {
      final String trimmed = line.trim();
      if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
        return trimmed;
      }
    }
    return '';
  }
}