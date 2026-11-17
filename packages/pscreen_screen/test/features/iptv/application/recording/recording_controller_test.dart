import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_screen/features/iptv/application/recording/recording_controller.dart';
import 'package:pscreen_screen/features/iptv/application/recording/recording_platform.dart';
import 'package:pscreen_screen/features/iptv/application/recording/recording_sink.dart';
import 'package:pscreen_screen/features/iptv/application/recording/recording_source_provider.dart';
import 'package:pscreen_screen/features/iptv/application/recording/recording_storage.dart';

/// 内存 playlist 源：url → m3u8 文本 / 分片字节。
class _FakeNetwork {
  _FakeNetwork({this.playlists = const <String, String>{}, this.segments = const <String, List<int>>{}});

  final Map<String, String> playlists;
  final Map<String, List<int>> segments;

  Future<String> fetchText(Uri url) async => playlists[url.toString()] ?? '';

  Future<List<int>> fetchBytes(Uri url) async => segments[url.toString()] ?? const <int>[1, 2, 3];
}

/// 假 SAF 写入：把分片累计到 [written]，验证边录边写。
class _FakeSaf implements SafPlatformOps {
  final List<int> written = <int>[];
  int? lastHandle;
  bool closed = false;

  @override
  Future<int> openOutputStream(String treeUri, String fileName) async {
    lastHandle = 7;
    return 7;
  }

  @override
  Future<void> appendBytes(int handle, List<int> bytes) async {
    written.addAll(bytes);
  }

  @override
  Future<void> closeStream(int handle) async {
    closed = true;
  }
}

/// 假平台：可控可用空间 + 文档目录 + SAF。
class _FakePlatform implements RecordingPlatform {
  _FakePlatform(this.dir, {this.free = -1, SafPlatformOps? saf})
      : _saf = saf ?? _FakeSaf();

  final Directory dir;
  final int free;
  final SafPlatformOps _saf;
  PickedDirectory? pickResult;

  @override
  Future<PickedDirectory?> pickDirectory() async => pickResult;

  @override
  Future<int> freeBytes({required RecordingLocation location, String? customUri}) async => free;

  @override
  Future<Directory> documentsDirectory() async => dir;

  @override
  SafPlatformOps get saf => _saf;

  @override
  Future<List<RecordedFile>> listFiles({
    required RecordingLocation location,
    String? customUri,
  }) async =>
      const <RecordedFile>[];

  @override
  Future<bool> deleteFile({required String uri, required RecordingLocation location}) async => true;
}

RecordingSource _source({
  String channel = 'CCTV-1',
  int index = 0,
  List<String>? sources,
  RecordingSourceOrigin origin = RecordingSourceOrigin.auto,
}) {
  final List<String> list = sources ?? <String>['https://cdn/x/0.m3u8', 'https://cdn/x/1.m3u8'];
  return RecordingSource(
    channelName: channel,
    originalUrl: list[index],
    sourceIndex: index,
    sources: list,
    origin: origin,
  );
}

Directory _tempDir() => Directory.systemTemp.createTempSync('rec_test_');

RecordingController _controller(
  _FakeNetwork net,
  Directory dir, {
  List<RecordingEvent>? events,
  bool Function()? parent,
}) {
  final RecordingController c = RecordingController(
    fetchText: net.fetchText,
    fetchBytes: net.fetchBytes,
    documentsDir: () async => dir,
    isParentMode: parent ?? (() => true),
    retryDelay: Duration.zero,
  );
  if (events != null) {
    c.onEvent = (RecordingEventData e) => events.add(e.type);
  }
  return c;
}

void main() {
  late Directory dir;

  setUp(() => dir = _tempDir());
  tearDown(() async {
    // Windows 下异步 close 可能滞后一瞬；重试几次再放弃，避免测试因文件占用误报。
    for (int attempt = 0; attempt < 5; attempt++) {
      try {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
        return;
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }
  });

  group('生命周期', () {
    test('start 成功进入 recording，stop 保存并回 idle', () async {
      final _FakeNetwork net = _FakeNetwork(
        playlists: <String, String>{
          'https://cdn/x/0.m3u8': '#EXTM3U\n#EXT-X-TARGETDURATION:4\nseg0.ts\n',
        },
        segments: <String, List<int>>{'https://cdn/x/seg0.ts': <int>[1, 2, 3, 4]},
      );
      final List<RecordingEvent> events = <RecordingEvent>[];
      final RecordingController c = _controller(net, dir, events: events);

      expect(await c.start(_source()), isTrue);
      expect(c.isRecording, isTrue);
      expect(c.state.value.channelName, 'CCTV-1');
      expect(c.state.value.bytes, 4);
      expect(events, contains(RecordingEvent.started));

      await c.stop();
      expect(c.isRecording, isFalse);
      expect(c.state.value.status, RecordingStatus.idle);
      expect(events, contains(RecordingEvent.saved));

      expect(
        dir.listSync(recursive: true).any((FileSystemEntity e) => e.path.endsWith('.ts')),
        isTrue,
        reason: '录制文件应落在私有目录',
      );
    });

    test('已在录制时再次 start 被拒（互斥）', () async {
      final _FakeNetwork net = _FakeNetwork(
        playlists: <String, String>{'https://cdn/x/0.m3u8': '#EXTM3U\nseg.ts\n'},
      );
      final List<RecordingEvent> events = <RecordingEvent>[];
      final RecordingController c = _controller(net, dir, events: events);

      expect(await c.start(_source()), isTrue);
      expect(await c.start(_source()), isFalse);
      expect(events, contains(RecordingEvent.duplicate));
      await c.stop();
    });

    test('儿童模式（isParentMode=false）拒绝 start', () async {
      final _FakeNetwork net = _FakeNetwork(
        playlists: <String, String>{'https://cdn/x/0.m3u8': '#EXTM3U\nseg.ts\n'},
      );
      final RecordingController c = _controller(net, dir, parent: () => false);
      expect(await c.start(_source()), isFalse);
      expect(c.isRecording, isFalse);
    });

    test('master playlist 自动选最低码率分支', () async {
      final _FakeNetwork net = _FakeNetwork(
        playlists: <String, String>{
          'https://cdn/x/0.m3u8': '#EXTM3U\n'
              '#EXT-X-STREAM-INF:BANDWIDTH=800000\nhigh.m3u8\n'
              '#EXT-X-STREAM-INF:BANDWIDTH=200000\nlow.m3u8\n',
          'https://cdn/x/low.m3u8': '#EXTM3U\nseg.ts\n',
        },
      );
      final RecordingController c = _controller(net, dir);
      expect(await c.start(_source()), isTrue);
      await c.stop();
    });

    test('加密流拒绝录制并发 unsupported', () async {
      final _FakeNetwork net = _FakeNetwork(
        playlists: <String, String>{
          'https://cdn/x/0.m3u8': '#EXTM3U\n'
              '#EXT-X-KEY:METHOD=AES-128,URI="k"\nseg.ts\n',
        },
      );
      final List<RecordingEvent> events = <RecordingEvent>[];
      final RecordingController c = _controller(net, dir, events: events);
      expect(await c.start(_source()), isFalse);
      expect(events, contains(RecordingEvent.unsupported));
    });
  });

  group('切源三级策略（D-11/12/13）', () {
    Future<RecordingController> startRecording(
      _FakeNetwork net,
      List<RecordingEvent> events,
    ) async {
      final RecordingController c = _controller(net, dir, events: events);
      await c.start(_source(index: 0));
      return c;
    }

    test('manual 切源被拦截：返回 false + switch_blocked，录制不中断', () async {
      final _FakeNetwork net = _FakeNetwork(
        playlists: <String, String>{'https://cdn/x/0.m3u8': '#EXTM3U\nseg.ts\n'},
      );
      final List<RecordingEvent> events = <RecordingEvent>[];
      final RecordingController c = await startRecording(net, events);

      final RecordingSource manual = _source(index: 1, origin: RecordingSourceOrigin.manual);
      expect(c.onSourceReport(manual), isFalse);
      expect(events, contains(RecordingEvent.switchBlocked));
      expect(c.isRecording, isTrue, reason: '被拦截时录制应继续');
      await c.stop(silent: true);
    });

    test('reload 同一源 signature 不变：放行且录制继续', () async {
      final _FakeNetwork net = _FakeNetwork(
        playlists: <String, String>{'https://cdn/x/0.m3u8': '#EXTM3U\nseg.ts\n'},
      );
      final List<RecordingEvent> events = <RecordingEvent>[];
      final RecordingController c = await startRecording(net, events);

      final RecordingSource reload = _source(index: 0, origin: RecordingSourceOrigin.reload);
      expect(reload.signature, c.recordingSource!.signature);
      expect(c.onSourceReport(reload), isTrue);
      expect(c.isRecording, isTrue);
      expect(events, isNot(contains(RecordingEvent.switchBlocked)));
      await c.stop(silent: true);
    });

    test('auto 真换源：放行，onSourceChanged 停录并保存', () async {
      final _FakeNetwork net = _FakeNetwork(
        playlists: <String, String>{'https://cdn/x/0.m3u8': '#EXTM3U\nseg.ts\n'},
      );
      final List<RecordingEvent> events = <RecordingEvent>[];
      final RecordingController c = await startRecording(net, events);

      final RecordingSource auto = _source(index: 1, origin: RecordingSourceOrigin.auto);
      expect(c.onSourceReport(auto), isTrue);
      await c.onSourceChanged(auto);
      expect(c.isRecording, isFalse);
      expect(events, contains(RecordingEvent.sourceSwitched));
    });

    test('切台（频道名变化）：停录保存为 saved', () async {
      final _FakeNetwork net = _FakeNetwork(
        playlists: <String, String>{'https://cdn/x/0.m3u8': '#EXTM3U\nseg.ts\n'},
      );
      final List<RecordingEvent> events = <RecordingEvent>[];
      final RecordingController c = await startRecording(net, events);

      final RecordingSource other = _source(channel: 'CCTV-5', origin: RecordingSourceOrigin.manual);
      expect(c.onSourceReport(other), isTrue, reason: '切台不应被 manual 拦截');
      await c.onSourceChanged(other);
      expect(c.isRecording, isFalse);
      expect(events, contains(RecordingEvent.saved));
    });

    test('signature 含源索引：同频道切源 signature 必变化', () {
      final RecordingSource a = _source(index: 0);
      final RecordingSource b = _source(index: 1);
      expect(a.signature, isNot(b.signature));
      // URL 带动态 token 变化时，只要列表与索引不变 signature 就稳定。
      final RecordingSource token = RecordingSource(
        channelName: 'CCTV-1',
        originalUrl: 'https://cdn/x/0.m3u8?token=abc',
        sourceIndex: 0,
        sources: <String>['https://cdn/x/0.m3u8', 'https://cdn/x/1.m3u8'],
        origin: RecordingSourceOrigin.reload,
      );
      expect(token.signature, a.signature);
    });
  });

  group('上报桥接', () {
    test('manual 被拒时 provider.current 不变、监听者不触发', () async {
      final _FakeNetwork net = _FakeNetwork(
        playlists: <String, String>{'https://cdn/x/0.m3u8': '#EXTM3U\nseg.ts\n'},
      );
      final RecordingController c = _controller(net, dir);
      final RecordingSourceProvider provider = RecordingSourceProvider(controller: c);
      await c.start(_source(index: 0));

      final RecordingSource first = _source(index: 0, origin: RecordingSourceOrigin.auto);
      expect(provider.report(first), isTrue);
      expect(provider.current!.sourceIndex, 0);

      int calls = 0;
      provider.attach((_) => calls++);
      final RecordingSource manual = _source(index: 1, origin: RecordingSourceOrigin.manual);
      expect(provider.report(manual), isFalse);
      expect(provider.current!.sourceIndex, 0);
      expect(calls, 0);
      expect(c.isRecording, isTrue);
      await c.stop(silent: true);
    });

    test('signature 变化时通知监听者；detach 后不再回调', () {
      final _FakeNetwork net = _FakeNetwork();
      final RecordingController c = _controller(net, dir);
      final RecordingSourceProvider provider = RecordingSourceProvider(controller: c);

      final RecordingSource s0 = _source(index: 0);
      expect(provider.report(s0), isTrue);
      int calls = 0;
      void listener(RecordingSource _) => calls++;
      provider.attach(listener);
      provider.report(_source(index: 0)); // 同 signature → 不通知
      expect(calls, 0);
      provider.report(_source(index: 1)); // 变 → 通知
      expect(calls, 1);

      provider.detach(listener);
      provider.report(_source(index: 0)); // 再变 → 已 detach
      expect(calls, 1);
    });
  });

  group('存储与空间（阶段一）', () {
    _FakeNetwork fakeNet() => _FakeNetwork(
          playlists: <String, String>{
            'https://cdn/x/0.m3u8': '#EXTM3U\n#EXT-X-TARGETDURATION:4\nseg.ts\n',
          },
          segments: <String, List<int>>{'https://cdn/x/seg.ts': <int>[9, 8, 7]},
        );

    test('低空间预检：可用空间低于阈值时拒绝开始并发 lowSpace 事件', () async {
      final List<RecordingEvent> events = <RecordingEvent>[];
      final _FakePlatform platform = _FakePlatform(dir, free: 10 * 1024 * 1024);
      final RecordingController c = RecordingController(
        fetchText: fakeNet().fetchText,
        fetchBytes: fakeNet().fetchBytes,
        storage: RecordingStorage(platform: platform),
        isParentMode: () => true,
        retryDelay: Duration.zero,
        lowSpaceBytes: 512 * 1024 * 1024,
      );
      c.onEvent = (RecordingEventData e) => events.add(e.type);

      expect(await c.start(_source()), isFalse);
      expect(events, contains(RecordingEvent.lowSpace));
      expect(c.isRecording, isFalse);
    });

    test('空间未知（free=-1）时不阻断录制', () async {
      final _FakePlatform platform = _FakePlatform(dir, free: -1);
      final RecordingController c = RecordingController(
        fetchText: fakeNet().fetchText,
        fetchBytes: fakeNet().fetchBytes,
        storage: RecordingStorage(platform: platform),
        isParentMode: () => true,
        retryDelay: Duration.zero,
      );
      expect(await c.start(_source()), isTrue);
      expect(c.state.value.bytes, 3);
      await c.stop(silent: true);
    });

    test('SAF 位置：分片写入原生流并在停止时关闭', () async {
      final _FakeSaf saf = _FakeSaf();
      final _FakePlatform platform = _FakePlatform(dir, free: -1, saf: saf);
      final RecordingStorage storage = RecordingStorage(platform: platform);
      // 直接持有 SAF sink 做写入验证（位置策略由宿主 AppSettings 切换，这里测 sink 行为）。
      final SafStreamSink sink = SafStreamSink(saf, 'content://tree', 'r.ts', 'USB');
      await sink.open();
      await sink.append(<int>[1, 2]);
      await sink.append(<int>[3]);
      await sink.close();
      expect(saf.written, <int>[1, 2, 3]);
      expect(saf.closed, isTrue);
      expect(sink.location, 'USB/r.ts');
      expect(storage.location, RecordingLocation.internal);
    });
  });

}
