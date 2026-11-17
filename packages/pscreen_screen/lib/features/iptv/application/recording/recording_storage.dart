import 'dart:io';

import 'package:pscreen_screen/core/utils/app_settings.dart';
import 'package:pscreen_screen/features/iptv/application/recording/recording_platform.dart';
import 'package:pscreen_screen/features/iptv/application/recording/recording_sink.dart';

/// 录制存储策略：根据 [AppSettings] 的位置配置解析落盘目标，创建写入器。
///
/// 不持有 context；位置选择结果写回 AppSettings 持久化。
class RecordingStorage {
  RecordingStorage({
    RecordingPlatform? platform,
    AppSettings? settings,
  })  : _platform = platform ?? MethodChannelRecordingPlatform(),
        _settings = settings ?? AppSettings.instance;

  final RecordingPlatform _platform;
  final AppSettings _settings;

  RecordingLocation get location => _settings.recordingLocation;
  String get customUri => _settings.recordingCustomUri;
  String get customDisplayName => _settings.recordingCustomDisplayName;
  int get maxFileBytes => _settings.recordingMaxFileMb * 1024 * 1024;
  int get lowSpaceBytes => _settings.recordingLowSpaceMb * 1024 * 1024;

  /// 当前位置的展示名（设置页显示用）。
  String get locationLabel {
    if (location == RecordingLocation.custom && customUri.isNotEmpty) {
      return customDisplayName;
    }
    return '应用内部存储';
  }

  /// 查询当前目标位置的可用字节；-1 表示未知（如原生未实现 / 非 Android）。
  Future<int> freeBytes() => _platform.freeBytes(
        location: location,
        customUri: location == RecordingLocation.custom ? customUri : null,
      );

  /// 打开目录选择器并把结果持久化为自定义位置。
  /// 返回 true 表示用户确认并保存；false 表示取消。
  Future<bool> pickAndSetDirectory() async {
    final PickedDirectory? picked = await _platform.pickDirectory();
    if (picked == null) return false;
    await _settings.setRecordingLocation(
      RecordingLocation.custom,
      uri: picked.uri,
      displayName: picked.displayName,
    );
    return true;
  }

  /// 切回应用内部存储。
  Future<void> useInternal() => _settings.setRecordingLocation(RecordingLocation.internal);

  /// 列出当前位置的已录文件。
  Future<List<RecordedFile>> listRecordings() => _platform.listFiles(
        location: location,
        customUri: location == RecordingLocation.custom ? customUri : null,
      );

  /// 删除指定录制文件。
  Future<bool> deleteRecording(String uri) => _platform.deleteFile(uri: uri, location: location);

  /// 设置单文件上限（MB）。
  Future<void> setMaxFileMb(int mb) => _settings.setRecordingMaxFileMb(mb);

  /// 设置低空间阈值（MB）。
  Future<void> setLowSpaceMb(int mb) => _settings.setRecordingLowSpaceMb(mb);

  /// 为指定文件创建写入器；调用方负责 [RecordingSink.open]、append、close。
  ///
  /// SAF 自定义目录用 content:// 流；app 内部用 dart:io 文件。
  Future<RecordingSink> createSink(String fileName) async {
    if (location == RecordingLocation.custom && customUri.isNotEmpty) {
      return SafStreamSink(_platform.saf, customUri, fileName, customDisplayName);
    }
    final Directory dir = await _platform.documentsDirectory();
    final Directory recordingDir = Directory('${dir.path}${Platform.pathSeparator}recordings');
    await recordingDir.create(recursive: true);
    final File file = File('${recordingDir.path}${Platform.pathSeparator}$fileName');
    return LocalFileSink(file);
  }
}
