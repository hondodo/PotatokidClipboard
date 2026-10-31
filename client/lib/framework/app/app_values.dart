import 'package:get_storage/get_storage.dart';
import 'package:potatokid_clipboard/framework/net/net_config.dart';

class AppValues {
  static String getHost() {
    try {
      return GetStorage().read<String>('baseHost') ??
          NetConfig.DEFAULT_BASE_HOST;
    } catch (e) {
      return NetConfig.DEFAULT_BASE_HOST;
    }
  }

  static void setHost(String host) {
    try {
      GetStorage().write('baseHost', host);
    } catch (e) {
      // ignore
    }
  }
}
