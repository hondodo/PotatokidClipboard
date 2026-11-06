import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

/// 安装包缓存：按 `releaseId + sha256` 落盘到 App 私有目录。
///
/// - 换版本（releaseId/sha256 变化）才重新下载；
/// - 文件被系统清理（`300008`）时缓存不存在，自然重下；
/// - `.part` 保留断点，供 Range 续传。
class AppUpdateCache {
  AppUpdateCache(this.root);

  /// App 私有目录下的 `app_update` 子目录。
  final Directory root;

  /// 默认位置：`getApplicationSupportDirectory()/app_update`。
  static Future<AppUpdateCache> open() async {
    final Directory base = await getApplicationSupportDirectory();
    final Directory dir = Directory('${base.path}${Platform.pathSeparator}app_update');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return AppUpdateCache(dir);
  }

  File finalFile({
    required String appId,
    required String releaseId,
    required String sha256,
  }) =>
      File('${root.path}${Platform.pathSeparator}${_safe(appId)}-${_safe(releaseId)}-$sha256.apk');

  File partFile({
    required String appId,
    required String releaseId,
    required String sha256,
  }) =>
      File('${finalFile(appId: appId, releaseId: releaseId, sha256: sha256).path}.part');

  /// 缓存命中：文件存在且 sha256 一致。
  Future<bool> isReady({
    required String appId,
    required String releaseId,
    required String sha256,
  }) async {
    final File file = finalFile(appId: appId, releaseId: releaseId, sha256: sha256);
    if (!file.existsSync() || file.lengthSync() == 0) return false;
    final String actual = await sha256OfFile(file);
    if (actual == sha256.toLowerCase()) return true;
    // 内容不符（下载被截断/文件被替换）：删掉，调用方会重新下载。
    try {
      file.deleteSync();
    } catch (_) {}
    return false;
  }

  /// 清理同一 appId 下其它版本的安装包/半成品，避免私有目录无限增长。
  Future<void> pruneOthers({required String appId, required String keepSha256}) async {
    try {
      if (!root.existsSync()) return;
      final String prefix = '${_safe(appId)}-';
      for (final FileSystemEntity entity in root.listSync()) {
        if (entity is! File) continue;
        final String name = entity.uri.pathSegments.last;
        if (!name.startsWith(prefix)) continue;
        if (name.contains(keepSha256)) continue;
        if (!name.endsWith('.apk') && !name.endsWith('.apk.part')) continue;
        try {
          entity.deleteSync();
        } catch (_) {}
      }
    } catch (_) {
      // 清理失败不影响下载主流程。
    }
  }

  File get pendingForceFile =>
      File('${root.path}${Platform.pathSeparator}pending_force.json');

  /// 持久化粘性强更：releaseId / 已下载路径 / 目标 build。
  Future<void> savePendingForce({
    required String appId,
    required String releaseId,
    required String path,
    required String sha256,
    required String version,
    required int build,
    String notes = '',
  }) async {
    try {
      await pendingForceFile.writeAsString(
        jsonEncode(<String, Object?>{
          'appId': appId,
          'releaseId': releaseId,
          'path': path,
          'sha256': sha256,
          'version': version,
          'build': build,
          'notes': notes,
        }),
        flush: true,
      );
    } catch (_) {
      // 持久化失败不影响本次安装/下载。
    }
  }

  Map<String, dynamic>? readPendingForce({required String appId}) {
    try {
      if (!pendingForceFile.existsSync()) return null;
      final Object? decoded = jsonDecode(pendingForceFile.readAsStringSync());
      if (decoded is! Map) return null;
      final Map<String, dynamic> data = Map<String, dynamic>.from(decoded);
      if (data['appId']?.toString() != appId) return null;
      return data;
    } catch (_) {
      return null;
    }
  }

  Future<void> clearPendingForce() async {
    try {
      if (pendingForceFile.existsSync()) pendingForceFile.deleteSync();
    } catch (_) {}
  }

  static String _safe(String value) => value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

  /// 流式计算文件 sha256（内存占用恒定）。
  static Future<String> sha256OfFile(File file) async {
    final Digest digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }
}
