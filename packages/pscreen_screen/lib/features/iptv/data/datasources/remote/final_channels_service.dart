import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:pscreen_screen/app/config/app_constants.dart';
import 'package:pscreen_screen/core/network/dio_manager.dart';
import 'package:pscreen_screen/core/network/net_exceptions.dart';
import 'package:pscreen_screen/core/utils/ptools_util.dart';
import 'package:pscreen_screen/features/iptv/domain/models/final_channels.dart';

/// 拉取结果：`payload == null` 表示服务端返回 304（本地版本仍是最新）。
class FinalChannelsFetchResult {
  const FinalChannelsFetchResult({this.payload});

  final FinalChannelsPayload? payload;

  bool get notModified => payload == null;
}

/// 拉取服务端合并后的最终频道列表。
///
/// 版本比对走标准 ETag：把本地 `version` 作为 `If-None-Match` 发过去，
/// 内容未变时服务端返回 304，不重复下载整份列表。
class FinalChannelsService {
  /// 首次/无缓存加载的等待上限（页面据此从加载态切到错误态）。
  static const Duration timeout = Duration(seconds: 10);

  Future<FinalChannelsFetchResult> fetch({
    String? version,
    bool retryOnUnlogin = true,
  }) async {
    final Map<String, dynamic> headers = <String, dynamic>{};
    if (version != null && version.isNotEmpty) {
      headers['If-None-Match'] = '"$version"';
    }

    final Response<dynamic>? response = await DioManager().getRaw(
      url: AppConstants.finalChannelsUrl,
      headers: headers,
      connectTimeout: timeout,
      receiveTimeout: timeout,
    );
    if (response?.statusCode == 304) {
      return const FinalChannelsFetchResult();
    }

    final String text = response?.data?.toString() ?? '';
    if (text.trim().isEmpty) {
      throw const HttpCodeException(200, '最终频道列表为空');
    }

    Map<String, dynamic>? map;
    try {
      final Object? decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) {
        map = decoded;
      } else if (decoded is Map) {
        map = Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      throw ContentNotJsonException(text);
    }
    if (map == null) throw ContentNotJsonException(text);

    final int code = map['code'] is num
        ? (map['code'] as num).toInt()
        : int.tryParse('${map['code']}') ?? PtoolsCode.success;
    if (code != PtoolsCode.success) {
      if (retryOnUnlogin && code == PtoolsCode.unlogin) {
        if (await PtoolsUtil.loginWithSaved()) {
          return fetch(version: version, retryOnUnlogin: false);
        }
      }
      throw PtoolsException(code, '${map['msg'] ?? '获取频道列表失败'}');
    }

    try {
      return FinalChannelsFetchResult(
        payload: FinalChannelsPayload.fromJson(map),
      );
    } on FormatException {
      throw ContentNotJsonException(text);
    }
  }
}
