import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:pscreen_screen/features/iptv/application/media_kind_probe.dart';
import 'package:pscreen_screen/features/iptv/application/playback_watchdog.dart';

void main() {
  group('视频节目结算', () {
    test('已判定视频但未进入播放 → 打开超时后回退', () {
      fakeAsync((FakeAsync async) {
        bool playing = false;
        final List<String> issues = <String>[];
        final MediaKindProbe probe = MediaKindProbe(onChanged: (_) {});
        final PlaybackWatchdog watchdog = PlaybackWatchdog(
          probe: probe,
          isPlaying: () => playing,
          onIssue: issues.add,
          timeoutOf: () => const Duration(seconds: 60),
        );
        probe.handleTracks(
          const Tracks(video: <VideoTrack>[VideoTrack('1', null, null)]),
        );
        watchdog.arm();
        async.elapse(const Duration(seconds: 60));
        expect(issues, <String>['打开60s后未进入播放']);
        watchdog.dispose();
      });
    });

    test('在播但无视频帧（黑屏）→ 到期回退', () {
      fakeAsync((FakeAsync async) {
        bool playing = true;
        final List<String> issues = <String>[];
        final MediaKindProbe probe = MediaKindProbe(onChanged: (_) {});
        final PlaybackWatchdog watchdog = PlaybackWatchdog(
          probe: probe,
          isPlaying: () => playing,
          onIssue: issues.add,
          timeoutOf: () => const Duration(seconds: 60),
        );
        probe.handleTracks(
          const Tracks(video: <VideoTrack>[VideoTrack('1', null, null)]),
        );
        watchdog.arm();
        async.elapse(const Duration(seconds: 60));
        expect(issues, <String>['打开60s后无视频帧(黑屏)']);
        watchdog.dispose();
      });
    });

    test('出过视频帧 → 宿主 cancel 后到期不再回退', () {
      fakeAsync((FakeAsync async) {
        bool playing = true;
        final List<String> issues = <String>[];
        final MediaKindProbe probe = MediaKindProbe(onChanged: (_) {});
        final PlaybackWatchdog watchdog = PlaybackWatchdog(
          probe: probe,
          isPlaying: () => playing,
          onIssue: issues.add,
          timeoutOf: () => const Duration(seconds: 60),
        );
        probe.handleTracks(
          const Tracks(video: <VideoTrack>[VideoTrack('1', null, null)]),
        );
        watchdog.arm();
        probe.handleWidth(1920); // 出画面 → 宿主取消看门狗
        watchdog.cancel();
        async.elapse(const Duration(seconds: 120));
        expect(issues, isEmpty);
        watchdog.dispose();
      });
    });

    test('超时时长由 timeoutOf 决定（代理模式更短），到期文案跟随', () {
      fakeAsync((FakeAsync async) {
        bool playing = false;
        final List<String> issues = <String>[];
        final MediaKindProbe probe = MediaKindProbe(onChanged: (_) {});
        final PlaybackWatchdog watchdog = PlaybackWatchdog(
          probe: probe,
          isPlaying: () => playing,
          onIssue: issues.add,
          timeoutOf: () => const Duration(seconds: 20), // 代理模式
        );
        probe.handleTracks(
          const Tracks(video: <VideoTrack>[VideoTrack('1', null, null)]),
        );
        watchdog.arm();
        async.elapse(const Duration(seconds: 19));
        expect(issues, isEmpty);
        async.elapse(const Duration(seconds: 1));
        expect(issues, <String>['打开20s后未进入播放']);
        watchdog.dispose();
      });
    });
  });

  group('音频节目结算', () {
    test('音频源已进入播放 → 到期视为成功（onAudioEstablished 每轮一次）', () {
      fakeAsync((FakeAsync async) {
        bool playing = true;
        final List<String> issues = <String>[];
        final List<bool> established = <bool>[];
        final MediaKindProbe probe = MediaKindProbe(onChanged: (_) {});
        final PlaybackWatchdog watchdog = PlaybackWatchdog(
          probe: probe,
          isPlaying: () => playing,
          onIssue: issues.add,
          timeoutOf: () => const Duration(seconds: 60),
          onAudioEstablished: () => established.add(true),
        );
        probe.handleTracks(
          const Tracks(audio: <AudioTrack>[AudioTrack('1', null, null)]),
        );
        watchdog.arm();
        async.elapse(const Duration(seconds: 60));
        expect(issues, isEmpty);
        expect(established, hasLength(1));
        watchdog.dispose();
      });
    });

    test('未在播放但音频输出参数就绪 → 也算成功', () {
      fakeAsync((FakeAsync async) {
        final List<String> issues = <String>[];
        final List<bool> established = <bool>[];
        final MediaKindProbe probe = MediaKindProbe(onChanged: (_) {});
        final PlaybackWatchdog watchdog = PlaybackWatchdog(
          probe: probe,
          isPlaying: () => false,
          onIssue: issues.add,
          timeoutOf: () => const Duration(seconds: 60),
          onAudioEstablished: () => established.add(true),
        );
        probe.handleTracks(
          const Tracks(audio: <AudioTrack>[AudioTrack('1', null, null)]),
        );
        probe.handleAudioParams(const AudioParams(channelCount: 2));
        watchdog.arm();
        async.elapse(const Duration(seconds: 60));
        expect(issues, isEmpty);
        expect(established, hasLength(1));
        watchdog.dispose();
      });
    });

    test('音频源无任何输出 → 到期回退', () {
      fakeAsync((FakeAsync async) {
        final List<String> issues = <String>[];
        final MediaKindProbe probe = MediaKindProbe(onChanged: (_) {});
        final PlaybackWatchdog watchdog = PlaybackWatchdog(
          probe: probe,
          isPlaying: () => false,
          onIssue: issues.add,
          timeoutOf: () => const Duration(seconds: 60),
        );
        probe.handleTracks(
          const Tracks(audio: <AudioTrack>[AudioTrack('1', null, null)]),
        );
        watchdog.arm();
        async.elapse(const Duration(seconds: 60));
        expect(issues, <String>['音频源打开60s后仍无音频输出']);
        watchdog.dispose();
      });
    });
  });

  group('判定未定（unknown）时的挂起结算', () {
    test('到期先挂起；判定落定为视频后由 notifyState 推进结算', () {
      fakeAsync((FakeAsync async) {
        bool playing = false;
        final List<String> issues = <String>[];
        final List<Duration> timeouts = <Duration>[];
        final MediaKindProbe probe = MediaKindProbe(onChanged: (_) {}, fallbackTimeout: const Duration(hours: 1));
        final PlaybackWatchdog watchdog = PlaybackWatchdog(
          probe: probe,
          isPlaying: () => playing,
          onIssue: issues.add,
          timeoutOf: () => const Duration(seconds: 60),
          onTimeout: () => timeouts.add(const Duration(seconds: 60)),
        );
        watchdog.arm();
        async.elapse(const Duration(seconds: 60));
        expect(timeouts, hasLength(1)); // 到期日志照常
        expect(issues, isEmpty); // 判定未定 → 挂起

        // 轨道表晚到：判定为视频，宿主喂事件后推进结算（仍未播放 → 回退）。
        probe.handleTracks(
          const Tracks(video: <VideoTrack>[VideoTrack('1', null, null)]),
        );
        watchdog.notifyState();
        expect(issues, <String>['打开60s后未进入播放']);
        watchdog.dispose();
      });
    });

    test('挂起期间退出播放状态后音频仍未出声 → notifyState 不提前结算', () {
      fakeAsync((FakeAsync async) {
        final List<String> issues = <String>[];
        final List<bool> established = <bool>[];
        final MediaKindProbe probe = MediaKindProbe(onChanged: (_) {}, fallbackTimeout: const Duration(hours: 1));
        final PlaybackWatchdog watchdog = PlaybackWatchdog(
          probe: probe,
          isPlaying: () => false,
          onIssue: issues.add,
          timeoutOf: () => const Duration(seconds: 60),
          onAudioEstablished: () => established.add(true),
        );
        watchdog.arm();
        async.elapse(const Duration(seconds: 60));
        expect(issues, isEmpty); // unknown → 挂起

        // 判定为音频但还没出声：不算落定，继续等。
        probe.handleTracks(
          const Tracks(audio: <AudioTrack>[AudioTrack('1', null, null)]),
        );
        watchdog.notifyState();
        expect(issues, isEmpty);
        expect(established, isEmpty);

        // 音频输出就绪 → 落定 → 结算为成功。
        probe.handleAudioParams(const AudioParams(channelCount: 2));
        watchdog.notifyState();
        expect(issues, isEmpty);
        expect(established, hasLength(1));
        watchdog.dispose();
      });
    });
  });
}
