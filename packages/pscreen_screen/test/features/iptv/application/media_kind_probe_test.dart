import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:pscreen_screen/features/iptv/application/media_kind_probe.dart';

/// 构造被测判定器，记录每次结论变化。
({MediaKindProbe probe, List<MediaKind> changes}) make({Duration fallbackTimeout = const Duration(seconds: 8)}) {
  final List<MediaKind> changes = <MediaKind>[];
  final MediaKindProbe probe = MediaKindProbe(
    onChanged: changes.add,
    fallbackTimeout: fallbackTimeout,
  );
  return (probe: probe, changes: changes);
}

/// 仅含伪轨（auto/no）的「空轨道表」——刚 open 时常是这样。
const Tracks emptyTracks = Tracks();

/// 只有真实音频轨的轨道表。
const Tracks audioOnlyTracks = Tracks(
  video: <VideoTrack>[VideoTrack('auto', null, null), VideoTrack('no', null, null)],
  audio: <AudioTrack>[AudioTrack('1', null, null)],
);

/// 真实视频轨 + 音频轨。
const Tracks videoTracks = Tracks(
  video: <VideoTrack>[VideoTrack('1', null, null)],
  audio: <AudioTrack>[AudioTrack('2', null, null)],
);

void main() {
  group('轨道判定', () {
    test('空轨道表（只有 auto/no 伪轨）不作任何结论', () {
      final (:probe, :changes) = make();
      probe.handleTracks(emptyTracks);
      expect(probe.kind, MediaKind.unknown);
      expect(changes, isEmpty);
    });

    test('有真实视频轨 → 视频', () {
      final (:probe, :changes) = make();
      probe.handleTracks(videoTracks);
      expect(probe.kind, MediaKind.video);
      expect(probe.hasVideoTrack, isTrue);
      expect(changes, <MediaKind>[MediaKind.video]);
    });

    test('无视频轨但有真实音频轨 → 音频（立即下结论）', () {
      final (:probe, :changes) = make();
      probe.handleTracks(audioOnlyTracks);
      expect(probe.kind, MediaKind.audio);
      expect(changes, <MediaKind>[MediaKind.audio]);
    });

    test('封面图轨（image/albumart）不算视频轨', () {
      final (:probe, :changes) = make();
      const Tracks albumArtTracks = Tracks(
        video: <VideoTrack>[VideoTrack('1', null, null, image: true)],
        audio: <AudioTrack>[AudioTrack('2', null, null)],
      );
      probe.handleTracks(albumArtTracks);
      expect(probe.kind, MediaKind.audio);
      expect(probe.hasVideoTrack, isFalse);
      expect(changes, <MediaKind>[MediaKind.audio]);
    });

    test('视频帧（width>0）→ 推翻一切确认为视频', () {
      final (:probe, :changes) = make();
      probe.handleTracks(audioOnlyTracks); // 先误判为音频
      probe.handleWidth(1920);
      expect(probe.kind, MediaKind.video);
      expect(probe.playedVideo, isTrue);
      expect(changes, <MediaKind>[MediaKind.audio, MediaKind.video]);
    });

    test('width 为 0 / null 不算出画面', () {
      final (:probe, :changes) = make();
      probe.handleWidth(0);
      probe.handleWidth(null);
      expect(probe.playedVideo, isFalse);
      expect(probe.kind, MediaKind.unknown);
      expect(changes, isEmpty);
    });
  });

  group('音频出声证据', () {
    test('空的 AudioParams 不算就绪', () {
      final MediaKindProbe probe = make().probe;
      probe.handleAudioParams(const AudioParams());
      expect(probe.audioParamsReady, isFalse);
    });

    test('任一字段非空即就绪', () {
      final MediaKindProbe probe = make().probe;
      probe.handleAudioParams(const AudioParams(channelCount: 2));
      expect(probe.audioParamsReady, isTrue);
    });
  });

  group('兜底窗口', () {
    test('窗口内轨道表无结论 → 按音频兜底', () {
      fakeAsync((FakeAsync async) {
        final (:probe, :changes) = make(fallbackTimeout: const Duration(seconds: 2));
        probe.reset();
        expect(probe.kind, MediaKind.unknown);
        async.elapse(const Duration(seconds: 2));
        expect(probe.kind, MediaKind.audio);
        expect(changes, <MediaKind>[MediaKind.audio]); // unknown 没变，不回调
      });
    });

    test('已有结论 / 已有视频证据 → 兜底不触发', () {
      fakeAsync((FakeAsync async) {
        final (:probe, :changes) = make(fallbackTimeout: const Duration(seconds: 2));
        probe.handleTracks(videoTracks);
        probe.reset();
        // reset 后轨道证据被清掉，但兜底若触发会改写结论——先补一帧视频证据。
        probe.handleWidth(640);
        async.elapse(const Duration(seconds: 5));
        expect(probe.kind, MediaKind.video);
        expect(changes, <MediaKind>[MediaKind.video, MediaKind.unknown, MediaKind.video]);
      });
    });

    test('reset 重新挂上兜底计时器（结论回到 unknown）', () {
      fakeAsync((FakeAsync async) {
        final (:probe, :changes) = make(fallbackTimeout: const Duration(seconds: 2));
        probe.handleTracks(audioOnlyTracks);
        probe.reset();
        expect(probe.kind, MediaKind.unknown);
        // 旧计时器已取消：再等 2s 触发的是 reset 后新挂的兜底 → audio。
        async.elapse(const Duration(seconds: 2));
        expect(probe.kind, MediaKind.audio);
        expect(changes, <MediaKind>[MediaKind.audio, MediaKind.unknown, MediaKind.audio]);
      });
    });

    test('reset 清空全部证据', () {
      final MediaKindProbe probe = make().probe;
      probe.handleTracks(videoTracks);
      probe.handleWidth(1920);
      probe.handleAudioParams(const AudioParams(sampleRate: 44100));
      probe.reset();
      expect(probe.hasVideoTrack, isFalse);
      expect(probe.playedVideo, isFalse);
      expect(probe.audioParamsReady, isFalse);
      expect(probe.kind, MediaKind.unknown);
      probe.dispose();
    });
  });

  group('decided（供看门狗挂起结算）', () {
    test('视频结论即时落定，与播放状态无关', () {
      final MediaKindProbe probe = make().probe;
      probe.handleTracks(videoTracks);
      expect(probe.decided(false), isTrue);
      expect(probe.decided(true), isTrue);
    });

    test('音频要「已进入播放或已出声」才落定', () {
      final MediaKindProbe probe = make().probe;
      probe.handleTracks(audioOnlyTracks);
      expect(probe.decided(false), isFalse);
      expect(probe.decided(true), isTrue); // 进入播放
      probe.handleAudioParams(const AudioParams(channelCount: 2));
      expect(probe.decided(false), isTrue); // 或音频输出就绪
    });

    test('未判定（unknown）不算落定', () {
      final MediaKindProbe probe = make().probe;
      expect(probe.decided(true), isFalse);
    });
  });
}
