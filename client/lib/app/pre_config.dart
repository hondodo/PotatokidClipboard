// ignore_for_file: avoid_print
import 'package:get_storage/get_storage.dart';
import 'package:potatokid_clipboard/framework/app/app_values.dart';
import 'package:potatokid_clipboard/framework/net/net_config.dart';
import 'package:potatokid_clipboard/utils/device_utils.dart';

class PreConfig {
  static Future<void> init() async {
    print('[${DateTime.now().toIso8601String()}] [PreConfig] init');
    await GetStorage.init();
    await DeviceUtils.instance.updateDeviceId();

    /// 初始化主机地址
    NetConfig.instance.baseHost = AppValues.getHost();
    print('初始化主机地址: ${NetConfig.instance.baseHost}');
    print('[${DateTime.now().toIso8601String()}] [PreConfig] init end');
  }
}
