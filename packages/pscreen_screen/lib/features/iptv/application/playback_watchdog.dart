import 'dart:async';

import 'package:pscreen_screen/features/iptv/application/media_kind_probe.dart';

/// 「打开后长时间没画面 / 没声音」看门狗（纯逻辑 + 计时器，不持有播放器）。
///
/// 每次 open 前 [arm]，超时时长由宿主的 [timeoutOf] 给出（电视端：直连 60s /
/// 代理 20s；触屏：固定 60s）。到期仍未达到「播放已确立」标准 → 判定坏源，
/// 通过 [onIssue] 交给重试状态机回退下一个源。出现真实视频帧后由宿主 [cancel]。
///
/// 结算标准按 [MediaKindProbe] 的判定分流（判定未定时先挂起，等宿主在
/// 播放状态 / 轨道 / 音频参数变化时调用 [notifyState] 推进）：
/// - **视频**：要已进入播放且出过真实视频帧（帧一到宿主就 cancel 了，走不到到期）；
/// - **音频**（广播台本就没有视频帧）：已进入播放或音频输出参数就绪即视为成功；
/// - **判定未定**（unknown）：默认按视频严格标准，判定落定后再结算。
///
/// 特别注意：黑屏时 stream 的 position 仍可能推进，故**不用 position 作健康信号**。
class PlaybackWatchdog {
  PlaybackWatchdog({
    required this.probe,
    required bool Function() isPlaying,
    required void Function(String reason) onIssue,
    required Duration Function() timeoutOf,
    this.onTimeout,
    this.onAudioEstablished,
  })  : _isPlaying = isPlaying,
        _onIssue = onIssue,
        _timeoutOf = timeoutOf;

  /// 配套的媒体类型判定器（结算标准按它当前的结论分流）。
  final MediaKindProbe probe;

  /// 到期时回调（宿主打日志用：此刻的 playing / width 等现场最有诊断价值）。
  final void Function()? onTimeout;

  /// 音频源「已确立播放」（进入播放或已出声）时的回调，每次 [arm] 最多一次
  /// （宿主通常用于记录播放成功）。
  final void Function()? onAudioEstablished;

  final bool Function() _isPlaying;
  final void Function(String reason) _onIssue;
  final Duration Function() _timeoutOf;

  Timer? _timer;

  /// 挂起的结算：判定未定时先存下来，[notifyState] 推进后再执行。
  void Function()? _pendingSettle;

  /// 本轮 [arm] 是否已上报过「音频已确立」。
  bool _establishedRecorded = false;

  /// 本轮生效的超时（到期文案里的秒数用它）。
  Duration _lastTimeout = Duration.zero;

  /// 启动一次看门狗（每次 open 前调用；超时取 [timeoutOf] 的当前值）。
  void arm() {
    _timer?.cancel();
    _pendingSettle = null;
    _establishedRecorded = false;
    _lastTimeout = _timeoutOf();
    _timer = Timer(_lastTimeout, _fire);
  }

  /// 解除（已确认出画面 / 换源重开 / 销毁）。
  void cancel() {
    _timer?.cancel();
    _timer = null;
    _pendingSettle = null;
  }

  /// 证据变化（进入播放 / 轨道表更新 / 音频输出就绪）时调用：
  /// 若结算因判定未定而挂起，判定落定后立即执行。
  void notifyState() {
    final void Function()? pending = _pendingSettle;
    if (pending == null) return;
    if (!probe.decided(_isPlaying())) return;
    _pendingSettle = null;
    pending();
  }

  void _fire() {
    onTimeout?.call();
    if (probe.kind == MediaKind.unknown) {
      // 判定还没落定：先挂起，等 [notifyState] 按最终判定结算。
      _pendingSettle = _settle;
      notifyState();
      return;
    }
    _settle();
  }

  /// 看门狗到期的实际结算（按已确定的媒体类型给不同标准）。
  void _settle() {
    final bool playing = _isPlaying();
    final int timeoutSec = _lastTimeout.inSeconds;
    if (probe.kind == MediaKind.audio) {
      // 音频节目：确有音频输出（播放状态 / 已解码出音频参数）即视为成功。
      if (playing || probe.audioParamsReady) {
        if (!_establishedRecorded) {
          _establishedRecorded = true;
          onAudioEstablished?.call();
        }
        return;
      }
      _onIssue('音频源打开${timeoutSec}s后仍无音频输出');
      return;
    }
    if (!playing) {
      _onIssue('打开${timeoutSec}s后未进入播放');
    } else if (!probe.playedVideo) {
      _onIssue('打开${timeoutSec}s后无视频帧(黑屏)');
    }
  }

  void dispose() => cancel();
}
