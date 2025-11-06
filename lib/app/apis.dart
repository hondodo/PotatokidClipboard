import 'package:potatokid_clipboard/framework/net/net_config.dart';

class Apis {
  static String login = '/api/login';
  static String autoLogin = '/api/autoLogin';
  static String getIpInfo = '/api/ipinfo';
  static String setClipboard = '/api/clipboard';
  static String getClipboardList = '/api/clipboards';
}

class Hosts {
  static String get baseHost => NetConfig.baseHost;
}

extension ApisExtension on String {
  String get inBaseHost {
    return '${Hosts.baseHost}$this';
  }
}
