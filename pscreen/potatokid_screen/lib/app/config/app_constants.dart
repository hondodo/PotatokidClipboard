/// 全局常量配置
class AppConstants {
  const AppConstants._();

  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 20);
  static const Duration sendTimeout = Duration(seconds: 20);

  static const int defaultMaxRetry = 2;

  /// 数据文件在本仓库 GitHub 上的「查看地址」前缀（`blob` 页面）。
  ///
  /// 该地址直接请求只会返回 HTML 页面，拿不到正文；请求前由
  /// `RawContentUrlResolver` 统一还原成 raw 直链。
  /// 用法：`'${AppConstants.githubDataBaseUrl}source.txt'`。
  static const String githubDataBaseUrl =
      'https://github.com/hondodo/PotatokidClipboard/blob/main/pscreen/potatokid_screen/assets/datas/';

  /// IPTV 直播播放列表（m3u），首页进入时自动加载并播放。
  ///
  /// 第一跳是 `source.txt`（GitHub 文件页），正文里是一个 GitHub release 下载地址；
  /// 两跳都由 `IptvApiService` 做 raw 还原 + 加速前缀。
  static const String iptvM3uUrl =
      // 旧的本地自建跳转（已弃用）：
      // 'http://ptool.w1.luyouxia.net/guovinapiurl.txt';
      // 'https://gh-proxy.com/raw.githubusercontent.com/vbskycn/iptv/refs/heads/master/tv/iptv4.m3u';
      '${AppConstants.githubDataBaseUrl}source.txt';

  /// GitHub 直链加速前缀，用法为 `{prefix}{原始 GitHub URL}`。
  ///
  /// `source.txt` 正文与正文里指向的 release 地址都在 GitHub，国内网络直连
  /// 会在连接阶段即超时；请求前套一层镜像前缀中转。留空则不做改写。
  static const String githubProxyPrefix = 'https://gh-proxy.com/';
}
