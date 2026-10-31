import 'package:potatokid_clipboard/app/apis.dart';
import 'package:potatokid_clipboard/framework/mixin/default_http_request.dart';
import 'package:potatokid_clipboard/framework/net/http_base_request.dart';
import 'package:potatokid_clipboard/framework/net/mixin/request_mixin.dart';
import 'package:potatokid_clipboard/pages/home/tabs/clipboard/model/clipboard_list_model.dart';
import 'package:potatokid_clipboard/utils/device_utils.dart';

class ClipboardRepository with RequestMixin {
  Future<dynamic> setClipboard(String text) async {
    final response = await Apis.setClipboard.inBaseHost.getHttpRequestWithApi(
      httpMethod: HttpMethod.POST,
      params: {
        'content': text,
        'os': DeviceUtils.instance.osType.value,
        'deviceId': DeviceUtils.instance.deviceId,
        'summary': '1',
      },
    ).sendDataRequest(this);
    return response;
  }

  Future<ClipboardListModel> getClipboardList({int? fromId}) async {
    final response =
        await Apis.getClipboardList.inBaseHost.getHttpRequestWithApi(
      params: {
        'fromId': fromId ?? 0,
        'summary': '1',
      },
    ).sendDataRequest(this);
    return ClipboardListModel.fromJson(response);
  }

  Future<String> getClipboardContent(int id) async {
    final response = await '${Apis.getClipboard}/$id'
        .inBaseHost
        .getHttpRequestWithApi()
        .sendDataRequest(this);
    final clipboard = response['clipboard'];
    if (clipboard is! Map<String, dynamic> ||
        clipboard['content'] is! String) {
      throw const FormatException('Invalid clipboard content');
    }
    return clipboard['content'] as String;
  }
}
