/// 全局常量配置
class AppConstants {
  const AppConstants._();

  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 20);
  static const Duration sendTimeout = Duration(seconds: 20);

  static const int defaultMaxRetry = 2;

  /// IPTV 直播播放列表（m3u），首页进入时自动加载并播放
  static const String iptvM3uUrl =
      'https://gh-proxy.com/raw.githubusercontent.com/vbskycn/iptv/refs/heads/master/tv/iptv4.m3u';
}
