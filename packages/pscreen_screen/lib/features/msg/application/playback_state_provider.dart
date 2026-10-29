import 'package:flutter/foundation.dart';

/// 设备本机当前的直播播放状态（仅内存，不落盘）。
///
/// 播放器通过 `ReportingService.notifyPlayback` 写入，状态上报器读取并随
/// `state` 帧下发给控制端，心跳文本也用它拼「播放：xxx」。
@immutable
class PlaybackSnapshot {
  const PlaybackSnapshot({
    required this.channel,
    required this.state,
    required this.ts,
  });

  /// 所属频道名（换台后旧快照作废）。
  final String channel;

  /// `play_start` / `play_ok` / `play_retry` / `play_fail`。
  final String state;

  /// 记录时间（毫秒）。
  final int ts;

  /// 中文文案，控制端可直接展示。
  String get label => switch (state) {
        'play_ok' => '播放正常',
        'play_start' => '起播中',
        'play_retry' => '重试中',
        'play_fail' => '播放失败',
        _ => '未知',
      };

  Map<String, Object?> toJson() => <String, Object?>{
        'channel': channel,
        'state': state,
        'label': label,
        'ts': ts,
      };
}

/// 播放状态单例：直播场景内才有值，离开直播或换台时清空。
class PlaybackStateProvider {
  PlaybackStateProvider._();

  static final PlaybackStateProvider instance = PlaybackStateProvider._();

  /// 变化通知（状态上报器据此立即推送 `state` 帧）。
  final ValueNotifier<PlaybackSnapshot?> notifier =
      ValueNotifier<PlaybackSnapshot?>(null);

  PlaybackSnapshot? get current => notifier.value;

  /// 记录最新播放状态：同频道反复 retry 直接覆盖，始终保留「最新状态」。
  void update(String channel, String state) {
    if (channel.isEmpty || state.isEmpty) return;
    notifier.value = PlaybackSnapshot(
      channel: channel,
      state: state,
      ts: DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// 离开直播/换台：清空，避免把上一频道的状态当成当前。
  void clear() {
    if (notifier.value != null) notifier.value = null;
  }
}
