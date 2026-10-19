/// 全局常量配置
class AppConstants {
  const AppConstants._();

  static const String nimAppKey = '8e3cb3b1cf5f8ae073c269ad461a69b5';

  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 20);
  static const Duration sendTimeout = Duration(seconds: 20);

  static const int defaultMaxRetry = 2;

  // /// 数据文件在 GitHub 上的「原始文件（raw）直链」前缀。
  // ///
  // /// 直接请求 `raw.githubusercontent.com` 取正文，**不经任何代理/中转**。
  // /// 万一以后配置里写成了 `blob` 文件页，也会由
  // /// `RawContentUrlResolver` 在请求前还原成同样的 raw 直链。
  // /// 用法：`'${AppConstants.githubDataBaseUrl}source.txt'`。
  // static const String githubDataBaseUrl =
  //     'https://raw.githubusercontent.com/hondodo/PotatokidClipboard/main/pscreen/potatokid_screen/assets/datas/';

  // /// IPTV 直播播放列表（m3u），首页进入时自动加载并播放。
  // ///
  // /// 第一跳是 `source.txt`（raw 直链），正文里是一个 GitHub release 下载地址；
  // /// 两跳都直接访问 GitHub，不做任何代理改写。
  // static const String iptvM3uUrl =
  //     '${AppConstants.githubDataBaseUrl}source.txt';

  /// github 访问不稳定，缓存方案也不稳定，
  static const String githubDataBaseUrl = 'https://ptool.w1.luyouxia.net/api/screen/';

  /// IPTV 直播播放列表（m3u），首页进入时自动加载并播放。
  ///
  /// 第一跳是 `source.txt`（raw 直链），返回一个下载地址
  static const String iptvM3uUrl = '${AppConstants.githubDataBaseUrl}source.txt';
}
