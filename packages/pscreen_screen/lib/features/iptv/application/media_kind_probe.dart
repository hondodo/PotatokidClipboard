import 'dart:async';

import 'package:media_kit/media_kit.dart';

/// 当前源的媒体类型（**只在运行时按真实轨道判定**，不看地址/名称）：
/// - [unknown]：刚打开，尚未判定，一律按**视频**的严格标准要求（默认视频）；
/// - [video]：确认存在真实视频轨（或已出画面）；
/// - [audio]：确认无视频轨，只有音频（广播台），看门狗改用宽松标准。
enum MediaKind { unknown, video, audio }

/// 媒体类型判定器（纯逻辑 + 计时器，不持有播放器）。
///
/// 宿主把播放器的 [Tracks] / width / [AudioParams] 事件喂进来，判定结果与证据
/// 暴露在字段上，结论变化时回调 [onChanged]（宿主据此刷新界面 / 记日志）。
///
/// 判定规则（所有客户端一致，抽自电视端实现）：
/// - **只看真实轨道**：mpv 的 tracks 恒含 `auto`/`no` 两条伪轨必须排除；
///   纯音频文件常带封面图（albumart/image），这类也不算视频轨；
/// - 轨道表在打开的瞬间就是完整的，是判定的**主入口**：「有真实视频轨 → 视频」、
///   「无视频轨但有真实音频轨 → 音频」立即下结论，不用干等兜底窗口；
///   空轨道表不作依据（否则视频源会被误判成音频、闪一下广播界面）；
/// - 出过视频帧（width>0）→ 有画面即确认视频，可推翻音频误判；
/// - [fallbackTimeout] 内轨道表始终没给出结论 → 兜底按音频处理（宽松标准），
///   否则 [MediaKind.unknown] 永远悬着会让看门狗到期后无法结算，坏源卡死在黑屏。
class MediaKindProbe {
  MediaKindProbe({required this.onChanged, this.fallbackTimeout = const Duration(seconds: 8)});

  /// 判定变化时回调（只在结论真正变化时触发）。
  final void Function(MediaKind kind) onChanged;

  /// 兜底判定窗口（轨道表一直无结论时按音频处理）。
  final Duration fallbackTimeout;

  /// 当前判定结果。
  MediaKind kind = MediaKind.unknown;

  /// 是否已收到过「真实视频轨」（排除伪轨与封面图）。
  bool hasVideoTrack = false;

  /// 黑屏判定：是否出现过真实视频帧（width>0）。
  bool playedVideo = false;

  /// 音频输出参数是否已就绪（音频节目「确实出声」的证据）。
  bool audioParamsReady = false;

  Timer? _fallback;

  /// 换源/换台后重置判定（回到 [MediaKind.unknown] 的严格标准），
  /// 清空全部证据并挂上兜底计时器。
  ///
  /// 地址/名称都不作依据：新源只能靠自己的真实轨道重新取证。
  void reset() {
    _fallback?.cancel();
    hasVideoTrack = false;
    playedVideo = false;
    audioParamsReady = false;
    _setKind(MediaKind.unknown);
    _fallback = Timer(fallbackTimeout, _onFallback);
  }

  /// 轨道表事件（判定主入口）。空表（既无视频也无真实音频）不作任何结论。
  void handleTracks(Tracks tracks) {
    final bool hasRealVideo = tracks.video.any((VideoTrack t) {
      if (t.id == 'auto' || t.id == 'no') return false;
      return !(t.image ?? false) && !(t.albumart ?? false);
    });
    if (hasRealVideo) {
      hasVideoTrack = true;
      _fallback?.cancel();
      _setKind(MediaKind.video);
      return;
    }
    // 没有视频轨但有真实音频轨 → 音频节目，立即下结论。
    final bool hasRealAudio = tracks.audio.any((AudioTrack t) => t.id != 'auto' && t.id != 'no');
    if (hasRealAudio) {
      _fallback?.cancel();
      _setKind(MediaKind.audio);
    }
  }

  /// 视频帧事件：width>0 即确认视频节目（推翻一切已有结论）。
  void handleWidth(int? width) {
    if (width == null || width <= 0) return;
    playedVideo = true;
    _fallback?.cancel();
    _setKind(MediaKind.video);
  }

  /// 音频输出参数事件：任一字段非空即记为「确实在出声」的证据。
  void handleAudioParams(AudioParams params) {
    if (params.channelCount != null || params.sampleRate != null || params.format != null) {
      audioParamsReady = true;
    }
  }

  /// 判定是否已**落定**到可结算状态（供看门狗在判定未定时挂起等待）：
  /// 视频结论即时落定；音频要等「已进入播放或已出声」。
  bool decided(bool playing) =>
      kind == MediaKind.video || (kind == MediaKind.audio && (audioParamsReady || playing));

  /// 兜底判定：窗口内轨道表无结论 → 按音频处理（宽松标准）。
  void _onFallback() {
    if (kind != MediaKind.unknown) return;
    // 已有视频证据（轨道/帧）时不算音频，防止极端时序误判。
    if (hasVideoTrack || playedVideo) return;
    _setKind(MediaKind.audio);
  }

  void _setKind(MediaKind next) {
    if (kind == next) return;
    kind = next;
    onChanged(next);
  }

  void dispose() => _fallback?.cancel();
}
