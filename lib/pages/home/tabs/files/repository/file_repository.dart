import 'package:dio/dio.dart';
import 'package:potatokid_clipboard/app/apis.dart';
import 'package:potatokid_clipboard/framework/mixin/default_http_request.dart';
import 'package:potatokid_clipboard/framework/net/dio/dio_manager.dart';
import 'package:potatokid_clipboard/framework/net/http_base_request.dart';
import 'package:potatokid_clipboard/framework/net/mixin/request_mixin.dart';
import 'package:potatokid_clipboard/pages/home/tabs/files/model/file_list_model.dart';

class FileRepository with RequestMixin {
  Future<FileListModel> getFileList() async {
    final response = await Apis.getFileList.inBaseHost
        .getHttpRequestWithApi(
          httpMethod: HttpMethod.GET,
        )
        .sendDataRequest(this);
    return FileListModel.fromJson(response);
  }

  String getDownloadUrl(String filename) {
    String url = Apis.downloadFile.inBaseHost;
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return '$url/$filename';
    // 如果未登录，那么必须传入用户名，否则会报错404
    // String username = Get.find<UserService>().user.value.name ?? 'guest';
    // return '$url/$username/$filename';
  }

  /// downloadToTempFile: 是否下载到临时文件，如果下载到临时文件，则下载成功后会自动重命名
  /// 如果downloadToTempFile为false，则不会下载到临时文件，直接下载到目标文件
  Future<bool> downloadFile({
    required String filename,
    required String saveFilename,
    ProgressCallback? onReceiveProgress,
    bool downloadToTempFile = true,
  }) async {
    String url = getDownloadUrl(filename);
    return DioManager().download(
        url: url,
        filename: saveFilename,
        onReceiveProgress: onReceiveProgress,
        downloadToTempFile: downloadToTempFile);
  }
}
