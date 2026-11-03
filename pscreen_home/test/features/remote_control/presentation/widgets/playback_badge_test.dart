// test/features/remote_control/presentation/widgets/playback_badge_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/features/remote_control/presentation/widgets/playback_badge.dart';
import 'package:pscreen_screen/core/network/realtime_channel.dart';

RealtimeDeviceState _device({
  required String kind,
  required String sceneKind,
  String label = '播放正常',
  String state = 'play_ok',
}) =>
    RealtimeDeviceState(
      account: '1000001',
      kind: kind,
      scene: <String, Object?>{'kind': sceneKind, 'title': '某场景'},
      playback: <String, Object?>{'channel': 'CCTV-1', 'state': state, 'label': label, 'ts': 0},
    );

void main() {
  group('playbackLabelOf（两处调用点共用的显示条件）', () {
    test('tv 非 live：仍显示上次播放状态', () {
      expect(
        playbackLabelOf(
          online: true,
          device: _device(kind: 'tv', sceneKind: 'screensaver'),
        ),
        '播放正常',
      );
    });

    test('tv live：显示', () {
      expect(
        playbackLabelOf(
          online: true,
          device: _device(kind: 'tv', sceneKind: 'live'),
        ),
        '播放正常',
      );
    });

    test('home 非 live：不显示（中控屏该场景不播放）', () {
      expect(
        playbackLabelOf(
          online: true,
          device: _device(kind: 'home', sceneKind: 'screensaver'),
        ),
        '',
      );
    });

    test('home live：正常显示', () {
      expect(
        playbackLabelOf(
          online: true,
          device: _device(kind: 'home', sceneKind: 'live'),
        ),
        '播放正常',
      );
    });

    test('未知端（kind 为空）：从严按 home 处理，非 live 不显示', () {
      expect(
        playbackLabelOf(
          online: true,
          device: _device(kind: '', sceneKind: 'screensaver'),
        ),
        '',
      );
    });

    test('离线：不显示', () {
      expect(
        playbackLabelOf(
          online: false,
          device: _device(kind: 'tv', sceneKind: 'live'),
        ),
        '',
      );
    });

    test('没有播放状态：不显示', () {
      expect(
        playbackLabelOf(
          online: true,
          device: RealtimeDeviceState(
            account: '1000001',
            kind: 'tv',
            scene: <String, Object?>{'kind': 'screensaver'},
          ),
        ),
        '',
      );
    });

    test('设备为空：不显示', () {
      expect(playbackLabelOf(online: true, device: null), '');
      expect(playbackLabelOf(online: false, device: null), '');
    });
  });
}
