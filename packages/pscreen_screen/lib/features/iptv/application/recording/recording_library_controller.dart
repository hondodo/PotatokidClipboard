import 'package:flutter/foundation.dart';

import 'package:pscreen_screen/features/iptv/application/recording/recording_platform.dart';
import 'package:pscreen_screen/features/iptv/application/recording/recording_storage.dart';

/// 录制库数据控制器（列表 / 删除 / 刷新）。
///
/// 共享包只提供数据与状态，不含任何 UI；两端各自实现列表页与播放跳转。
class RecordingLibraryController {
  RecordingLibraryController({RecordingStorage? storage})
      : _storage = storage ?? RecordingStorage();

  final RecordingStorage _storage;

  static final RecordingLibraryController instance = RecordingLibraryController();

  final ValueNotifier<List<RecordedFile>> items =
      ValueNotifier<List<RecordedFile>>(const <RecordedFile>[]);
  final ValueNotifier<bool> loading = ValueNotifier<bool>(false);

  /// 当前所在位置（决定列举哪个目录）。
  RecordingLocation get location => _storage.location;
  String get locationLabel => _storage.locationLabel;

  /// 刷新列表。
  Future<void> refresh() async {
    loading.value = true;
    try {
      items.value = await _storage.listRecordings();
    } finally {
      loading.value = false;
    }
  }

  /// 删除一条；成功后自动刷新。
  Future<bool> delete(RecordedFile file) async {
    final bool ok = await _storage.deleteRecording(file.uri);
    if (ok) await refresh();
    return ok;
  }

  /// 供 UI 拼文件大小（如 12.4 MB）。
  static String formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// 供 UI 拼修改时间（本地化由宿主负责，这里只给 DateTime）。
  static DateTime modifiedTime(RecordedFile file) =>
      DateTime.fromMillisecondsSinceEpoch(file.modifiedMs);
}
