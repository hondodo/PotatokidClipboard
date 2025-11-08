import 'package:potatokid_clipboard/framework/net/net_config.dart';

class Apis {
  static String login = '/api/login';
  static String autoLogin = '/api/autoLogin';
  static String getIpInfo = '/api/ipinfo';
  static String setClipboard = '/api/clipboard';
  static String getClipboardList = '/api/clipboards';
}

class Hosts {
  static String get baseHost => NetConfig.instance.baseHost;
}

extension ApisExtension on String {
  String get inBaseHost {
    String baseHost = Hosts.baseHost;
    while (baseHost.endsWith('/')) {
      baseHost = baseHost.substring(0, baseHost.length - 1);
    }
    if (startsWith('/')) {
      return '$baseHost$this';
    }
    return '$baseHost/$this';
  }
}
