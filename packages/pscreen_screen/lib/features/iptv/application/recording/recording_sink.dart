import 'dart:io';

import 'package:pscreen_screen/features/iptv/application/recording/recording_platform.dart';

/// 录制写入目标。
///
/// 两种实现：
/// - [LocalFileSink]：app 私有目录，dart:io 直接写（默认，零原生依赖）；
/// - [SafStreamSink]：SAF（U 盘 / SD 卡 / 用户自选目录），经 MethodChannel
///   让原生持有 ContentResolver OutputStream 写入（content:// 无法用 dart:io 写）。
abstract class RecordingSink {
  /// 追加一段字节。必须串行调用。
  Future<void> append(List<int> bytes);

  /// 冲刷并关闭。幂等。
  Future<void> close();

  /// 展示用位置（SnackBar / 录制列表里显示）。
  String get location;
}

/// app 私有目录写入器。
class LocalFileSink implements RecordingSink {
  LocalFileSink(this.file);

  final File file;
  RandomAccessFile? _raf;

  Future<void> open() async {
    _raf ??= file.openSync(mode: FileMode.append);
  }

  @override
  Future<void> append(List<int> bytes) async {
    _raf?.writeFromSync(bytes);
  }

  @override
  Future<void> close() async {
    final RandomAccessFile? raf = _raf;
    _raf = null;
    if (raf == null) return;
    try {
      await raf.flush();
    } catch (_) {
      // 冲刷失败仍需尝试关闭。
    }
    try {
      await raf.close();
    } catch (_) {
      // 关闭失败不影响状态收尾。
    }
  }

  @override
  String get location => file.path;
}

/// SAF 写入器：原生持有 OutputStream，Dart 只传分片字节。
///
/// 写入通道由 [SafPlatformOps] 提供（见 recording_platform.dart），便于单测注入。
class SafStreamSink implements RecordingSink {
  SafStreamSink(this._ops, this._treeUri, this._fileName, this._displayName);

  final SafPlatformOps _ops;
  final String _treeUri;
  final String _fileName;
  final String _displayName;
  int? _handle;

  Future<void> open() async {
    _handle ??= await _ops.openOutputStream(_treeUri, _fileName);
  }

  @override
  Future<void> append(List<int> bytes) async {
    final int? handle = _handle;
    if (handle == null) return;
    await _ops.appendBytes(handle, bytes);
  }

  @override
  Future<void> close() async {
    final int? handle = _handle;
    _handle = null;
    if (handle != null) await _ops.closeStream(handle);
  }

  @override
  String get location => '$_displayName/$_fileName';
}
