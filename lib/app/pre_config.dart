import 'package:potatokid_clipboard/framework/app/app_values.dart';
import 'package:potatokid_clipboard/framework/net/net_config.dart';
import 'package:potatokid_clipboard/utils/device_utils.dart';

class PreConfig {
  static Future<void> init() async {
    await DeviceUtils.instance.updateDeviceId();

    /// 初始化主机地址
    NetConfig.baseHost = AppValues.getHost();
  }
}
