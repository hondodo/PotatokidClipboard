import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// 录制存储位置：app 私有目录，或 SAF 授权的自定义目录（U 盘 / SD 卡等）。
enum RecordingLocation { internal, custom }

/// 一条已录文件记录。
class RecordedFile {
  const RecordedFile({
    required this.uri,
    required this.name,
    required this.size,
    required this.modifiedMs,
  });

  /// internal 为绝对路径；custom 为 content:// document uri。
  final String uri;
  final String name;
  final int size;
  final int modifiedMs;

  bool get isSaf => uri.startsWith('content://');
}

/// 目录选择结果（原生 SAF 返回）。
class PickedDirectory {
  const PickedDirectory({required this.uri, required this.displayName});

  /// SAF tree URI（`content://...`）。
  final String uri;

  /// 展示名（如「USB Drive」「内部存储/Download」）。
  final String displayName;
}

/// 录制平台能力接口：目录选择 / 可用空间 / SAF 写入 / 本地路径。
///
/// 共享包只依赖此接口；默认实现走 MethodChannel（两端原生实现），
/// 单测可注入假实现完全离线运行。
abstract class RecordingPlatform {
  /// 打开系统目录选择器（SAF ACTION_OPEN_DOCUMENT_TREE）。
  /// 返回 null 表示用户取消；uri 持久授权由原生负责。
  Future<PickedDirectory?> pickDirectory();

  /// 目标位置的可用字节数；查询失败返回 -1（controller 据此跳过低空间判断）。
  Future<int> freeBytes({required RecordingLocation location, String? customUri});

  /// 获取 app 文档目录（app 私有），供 internal 位置落盘。
  Future<Directory> documentsDirectory();

  /// SAF 写入通道。
  SafPlatformOps get saf;

  /// 列举当前（或指定）位置的已录文件，按修改时间倒序。
  Future<List<RecordedFile>> listFiles({
    required RecordingLocation location,
    String? customUri,
  });

  /// 删除一条录制；返回是否成功。
  Future<bool> deleteFile({
    required String uri,
    required RecordingLocation location,
  });
}

/// SAF 写入句柄的原生通道（见 recording_sink.dart 的 [SafStreamOps]）。
abstract class SafPlatformOps {
  Future<int> openOutputStream(String treeUri, String fileName);
  Future<void> appendBytes(int handle, List<int> bytes);
  Future<void> closeStream(int handle);
}

/// 默认平台实现：MethodChannel('potatokid/recording')。
///
/// 原生（两端 MainActivity）需实现以下方法：
/// - `pickDirectory()` → `Map{uri, displayName}` 或 null
/// - `freeBytes` {location:'internal'|'custom', customUri} → int（-1 表示未知）
/// - SAF: `openOutputStream` {uri,name}→int / `appendBytes` {handle,bytes} /
///   `closeStream` {handle}
class MethodChannelRecordingPlatform implements RecordingPlatform {
  MethodChannelRecordingPlatform({MethodChannel? channel, this.documentsDirProvider})
      : _channel = channel ?? const MethodChannel('potatokid/recording');

  final MethodChannel _channel;

  /// 可注入的文档目录提供者；默认用 path_provider。
  final Future<Directory> Function()? documentsDirProvider;

  @override
  Future<Directory> documentsDirectory() async {
    if (documentsDirProvider != null) return documentsDirProvider!();
    // path_provider 在共享包已是直接依赖，真机可用；测试环境注入 provider 规避。
    return getApplicationDocumentsDirectory();
  }

  @override
  Future<PickedDirectory?> pickDirectory() async {
    try {
      final Map<Object?, Object?>? raw = await _channel
          .invokeMethod<Map<Object?, Object?>>('pickDirectory');
      if (raw == null) return null;
      final String? uri = raw['uri'] as String?;
      if (uri == null || uri.isEmpty) return null;
      return PickedDirectory(
        uri: uri,
        displayName: (raw['displayName'] as String?) ?? '自定义目录',
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<int> freeBytes({
    required RecordingLocation location,
    String? customUri,
  }) async {
    try {
      final int? value = await _channel.invokeMethod<int>('freeBytes', <String, Object?>{
        'location': location.name,
        'customUri': customUri,
      });
      return value ?? -1;
    } catch (_) {
      // 原生未实现 / 测试无 binding / 查询失败：返回 -1 让调用方跳过空间判断。
      return -1;
    }
  }

  @override
  SafPlatformOps get saf => _MethodChannelSafOps(_channel);

  @override
  Future<List<RecordedFile>> listFiles({
    required RecordingLocation location,
    String? customUri,
  }) async {
    try {
      final List<Object?>? raw = await _channel.invokeMethod<List<Object?>>(
        'listFiles',
        <String, Object?>{'location': location.name, 'customUri': customUri},
      );
      if (raw == null) return const <RecordedFile>[];
      return raw.whereType<Map<Object?, Object?>>().map((Map<Object?, Object?> m) {
        return RecordedFile(
          uri: (m['uri'] as String?) ?? '',
          name: (m['name'] as String?) ?? '',
          size: (m['size'] as int?) ?? 0,
          modifiedMs: (m['modified'] as int?) ?? 0,
        );
      }).where((RecordedFile f) => f.uri.isNotEmpty).toList();
    } catch (_) {
      return const <RecordedFile>[];
    }
  }

  @override
  Future<bool> deleteFile({
    required String uri,
    required RecordingLocation location,
  }) async {
    try {
      final bool? ok = await _channel.invokeMethod<bool>('deleteFile', <String, Object?>{
        'uri': uri,
        'location': location.name,
      });
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }
}

class _MethodChannelSafOps implements SafPlatformOps {
  _MethodChannelSafOps(this._channel);

  final MethodChannel _channel;

  @override
  Future<int> openOutputStream(String treeUri, String fileName) async {
    final int? handle = await _channel.invokeMethod<int>(
      'openOutputStream',
      <String, Object?>{'uri': treeUri, 'name': fileName},
    );
    if (handle == null) throw StateError('SAF 打开输出流失败');
    return handle;
  }

  @override
  Future<void> appendBytes(int handle, List<int> bytes) async {
    await _channel.invokeMethod<void>('appendBytes', <String, Object?>{
      'handle': handle,
      'bytes': Uint8List.fromList(bytes),
    });
  }

  @override
  Future<void> closeStream(int handle) async {
    await _channel.invokeMethod<void>('closeStream', <String, Object?>{'handle': handle});
  }
}
