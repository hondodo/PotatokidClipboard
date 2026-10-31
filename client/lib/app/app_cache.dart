import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:potatokid_clipboard/framework/utils/app_log.dart';
import 'package:potatokid_clipboard/user/user_service.dart';

class AppCache {
  static final AppCache _instance = AppCache._internal();
  factory AppCache() {
    return _instance;
  }
  AppCache._internal();

  static AppCache get instance => _instance;

  static const String webFileTolocalFilenameKey = 'webFileTolocalFilename';

  String? getWebFileTolocalFilename(String filename) {
    try {
      int? userId = Get.find<UserService>().user.value.id;
      if (userId == null) {
        return null; // 未登录，无法获取本地文件名
      }
      String key = '$webFileTolocalFilenameKey:$userId:$filename';
      return GetStorage().read<String>(key);
    } catch (e) {
      Log.e('getWebFileTolocalFilename error: $e');
      return null;
    }
  }

  void setWebFileTolocalFilename(String filename, String localFilename) {
    int? userId = Get.find<UserService>().user.value.id;
    if (userId == null) {
      return; // 未登录，无法设置本地文件名
    }
    String key = '$webFileTolocalFilenameKey:$userId:$filename';
    GetStorage().write(key, localFilename);
  }
}
