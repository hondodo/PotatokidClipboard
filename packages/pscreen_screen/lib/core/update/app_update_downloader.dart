import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:pscreen_screen/core/update/app_update_models.dart';
import 'package:pscreen_screen/core/update/app_update_cache.dart';

/// 下载失败分类：决定是否重试、是否需要重新取链。
class AppUpdateDownloadException implements Exception {
  const AppUpdateDownloadException(this.message, {this.retryable = true, this.needRenewUrl = false});

  final String message;
  final bool retryable;
  final bool needRenewUrl;

  @override
  String toString() => 'AppUpdateDownloadException($message)';
}

/// sha256 不一致（服务端换包 / 下载被劫持 / 文件损坏）：删掉重下。
class AppUpdateShaMismatchException extends AppUpdateDownloadException {
  const AppUpdateShaMismatchException() : super('安装包校验失败（sha256 不一致）', retryable: true);
}

/// 安装包下载器：签名直链直连 yuntu，支持 Range 续传、流式 sha256 校验、
/// 可选限速（默认不限速）。
class AppUpdateDownloader {
  AppUpdateDownloader({Dio? dio, this.maxBytesPerSecond})
      : _dio = dio ??
            Dio(
              BaseOptions(
                // 大文件必须用流式读取，不能开自动解压/转换。
                responseType: ResponseType.stream,
                // 视频/APK 常被 CDN 分块压缩传输，Range 续传要求 identity。
                headers: <String, dynamic>{'accept-encoding': 'identity'},
                connectTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 60),
              ),
            );

  final Dio _dio;

  /// 可选限速（字节/秒），null 表示不限速。
  final int? maxBytesPerSecond;

  /// 下载（或复用缓存）并返回校验通过的安装包文件。
  ///
  /// [renewDownload] 在签名过期（403）/文件被清理（410）时重新取链；
  /// 局部文件保留在 `.part`，重试时自动带 `Range` 续传。
  Future<File> download({
    required String appId,
    required AppUpdateCheckResult result,
    required AppUpdateCache cache,
    required void Function(int received, int total) onProgress,
    Future<AppUpdateDownload?> Function()? renewDownload,
  }) async {
    AppUpdateDownload? download = result.download;
    if (download == null || !download.isUsable) {
      throw const AppUpdateDownloadException('服务端未返回可用的下载地址');
    }
    final String releaseId = result.latest?.releaseId ?? '';
    final String sha = download.sha256;

    if (await cache.isReady(appId: appId, releaseId: releaseId, sha256: sha)) {
      return cache.finalFile(appId: appId, releaseId: releaseId, sha256: sha);
    }

    int renewCount = 0;
    for (int attempt = 0; attempt < 4; attempt++) {
      final AppUpdateDownload current = download!;
      final File part = cache.partFile(appId: appId, releaseId: releaseId, sha256: current.sha256);
      int existing = part.existsSync() ? part.lengthSync() : 0;
      if (existing > current.size) {
        part.deleteSync();
        existing = 0;
      }

      Response<ResponseBody> response;
      try {
        response = await _dio.get<ResponseBody>(
          current.url,
          options: Options(
            responseType: ResponseType.stream,
            validateStatus: (int? status) => status != null,
            headers: <String, dynamic>{
              'accept-encoding': 'identity',
              if (existing > 0) HttpHeaders.rangeHeader: 'bytes=$existing-',
            },
          ),
        );
      } on DioException catch (error) {
        throw AppUpdateDownloadException(error.message ?? '下载请求失败');
      }

      final int status = response.statusCode ?? 0;
      if (status == 403 || status == 410) {
        // 签名过期（600s TTL）或安装包被空间清理：重新查询拿新链，
        // 不清空 .part，续传继续。
        if (renewDownload == null || renewCount >= 1) {
          throw AppUpdateDownloadException(
            status == 410 ? '安装包已被服务端清理（300008）' : '下载签名已过期',
            needRenewUrl: true,
          );
        }
        renewCount += 1;
        final AppUpdateDownload? fresh = await renewDownload();
        if (fresh == null || !fresh.isUsable) {
          throw const AppUpdateDownloadException('重新获取下载地址失败', needRenewUrl: true);
        }
        download = fresh;
        continue;
      }
      if (status == 416) {
        // 本地半成品比服务端文件还长：删掉从头下。
        if (part.existsSync()) part.deleteSync();
        continue;
      }
      if (status == 429) {
        throw const AppUpdateDownloadException('下载被限流（429），稍后重试');
      }
      if (status < 200 || status >= 300) {
        throw AppUpdateDownloadException('下载失败（HTTP $status）');
      }

      // 200 = 服务端忽略 Range，从头开始；206 = 按 Range 续传。
      final bool append = status == 206 && existing > 0;
      if (!append) existing = 0;
      final int total = current.size > 0
          ? current.size
          : (existing + (response.headers.value(Headers.contentLengthHeader) == null
              ? 0
              : int.tryParse(response.headers.value(Headers.contentLengthHeader)!) ?? 0));
      final int already = existing;
      int received = already;
      // 限速只按本次连接实际写入的字节计算；否则续传时会把历史字节当成
      // 「已落后」，在 1MiB/s 下可能休眠数小时。
      int sessionBytes = 0;

      final RandomAccessFile raf = part.openSync(mode: append ? FileMode.append : FileMode.write);
      final Stopwatch clock = Stopwatch()..start();
      try {
        try {
          await for (final Uint8List chunk in response.data!.stream) {
            raf.writeFromSync(chunk);
            received += chunk.length;
            sessionBytes += chunk.length;
            onProgress(received, total);
            await _throttle(clock, sessionBytes);
          }
        } on DioException catch (error) {
          throw AppUpdateDownloadException(error.message ?? '下载中断');
        }
      } finally {
        await raf.close();
      }

      if (total > 0 && received < total) {
        throw AppUpdateDownloadException('下载中断（$received/$total），已保留断点');
      }

      final String actual = await AppUpdateCache.sha256OfFile(part);
      if (actual.toLowerCase() != current.sha256.toLowerCase()) {
        // 校验失败：删除半成品，交由上层重下一次（防止死循环用 attempt 计数）。
        try {
          part.deleteSync();
        } catch (_) {}
        throw const AppUpdateShaMismatchException();
      }

      final File target = cache.finalFile(appId: appId, releaseId: releaseId, sha256: current.sha256);
      if (target.existsSync()) target.deleteSync();
      await part.rename(target.path);
      await cache.pruneOthers(appId: appId, keepSha256: current.sha256);
      return target;
    }
    throw const AppUpdateDownloadException('下载失败，稍后重试');
  }

  /// 默认不限速；配置了 [maxBytesPerSecond] 时按「本次连接」累计字节与耗时做
  /// 节流，只在落后超过 40ms 时延迟：平均速率受控，但允许最多约 40ms 的突发。
  Future<void> _throttle(Stopwatch clock, int sessionBytes) async {
    final int? limit = maxBytesPerSecond;
    if (limit == null || limit <= 0) return;
    final int expectedMs = (sessionBytes * 1000) ~/ limit;
    final int actualMs = clock.elapsedMilliseconds;
    final int behind = expectedMs - actualMs;
    if (behind > 40) await Future<void>.delayed(Duration(milliseconds: behind));
  }
}
