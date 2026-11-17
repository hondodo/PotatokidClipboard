import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_screen/features/iptv/application/recording/hls_playlist.dart';

void main() {
  group('master playlist', () {
    test('解析分支带宽 + 相对 URL resolve，并选出最低码率', () {
      const String text = '''
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=1280x720
high/stream.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=300000,RESOLUTION=640x360
low/stream.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=1500000
ultra/stream.m3u8
''';
      final HlsPlaylist p = parsePlaylist(text, Uri.parse('https://cdn.example.com/live/ch1/master.m3u8'));

      expect(p.isMaster, isTrue);
      expect(p.variants, hasLength(3));
      expect(p.variants[0].bandwidth, 800000);
      expect(p.variants[1].bandwidth, 300000);
      expect(p.variants[0].url.toString(), 'https://cdn.example.com/live/ch1/high/stream.m3u8');
      expect(p.selectedVariantUrl.toString(), 'https://cdn.example.com/live/ch1/low/stream.m3u8');
      expect(p.segments, isEmpty);
    });

    test('分支缺 BANDWIDTH 时视为无穷大，有带宽的优先', () {
      const String text = '''
#EXTM3U
#EXT-X-STREAM-INF
nobw.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=500000
bw.m3u8
''';
      final HlsPlaylist p = parsePlaylist(text, Uri.parse('https://x.com/a/m.m3u8'));
      expect(p.variants[0].bandwidth, isNull);
      expect(p.selectedVariantUrl.toString(), 'https://x.com/a/bw.m3u8');
    });

    test('全部无带宽时退回第一个分支', () {
      const String text = '''
#EXTM3U
#EXT-X-STREAM-INF
one.m3u8
#EXT-X-STREAM-INF
two.m3u8
''';
      final HlsPlaylist p = parsePlaylist(text, Uri.parse('https://x.com/a/m.m3u8'));
      expect(p.selectedVariantUrl.toString(), 'https://x.com/a/one.m3u8');
    });
  });

  group('media playlist', () {
    test('解析分片、相对 URL、media sequence 与 target duration', () {
      const String text = '''
#EXTM3U
#EXT-X-VERSION:3
#EXT-X-TARGETDURATION:8
#EXT-X-MEDIA-SEQUENCE:1024
#EXTINF:8.0,
seg1024.ts
#EXTINF:8.0,
seg1025.ts
#EXTINF:4.0,
/absolute/seg1026.ts
''';
      final HlsPlaylist p = parsePlaylist(text, Uri.parse('https://cdn.example.com/live/ch1/index.m3u8'));

      expect(p.isMaster, isFalse);
      expect(p.mediaSequence, 1024);
      expect(p.targetDuration, 8);
      expect(p.segments, hasLength(3));
      expect(p.segments[0].toString(), 'https://cdn.example.com/live/ch1/seg1024.ts');
      expect(p.segments[1].toString(), 'https://cdn.example.com/live/ch1/seg1025.ts');
      expect(p.segments[2].toString(), 'https://cdn.example.com/absolute/seg1026.ts');
      expect(p.encrypted, isFalse);
      expect(p.selectedVariantUrl.toString(), 'https://cdn.example.com/live/ch1/index.m3u8');
    });

    test('CRLF 换行同样可解析', () {
      final String text = '#EXTM3U\r\n#EXT-X-MEDIA-SEQUENCE:7\r\nseg7.ts\r\n';
      final HlsPlaylist p = parsePlaylist(text, Uri.parse('https://x.com/live/i.m3u8'));
      expect(p.mediaSequence, 7);
      expect(p.segments.single.toString(), 'https://x.com/live/seg7.ts');
    });
  });

  group('加密检测', () {
    test('AES-128 KEY 标记为加密', () {
      const String text = '''
#EXTM3U
#EXT-X-KEY:METHOD=AES-128,URI="https://x.com/key"
#EXTINF:8.0,
seg.ts
''';
      final HlsPlaylist p = parsePlaylist(text, Uri.parse('https://x.com/i.m3u8'));
      expect(p.encrypted, isTrue);
    });

    test('METHOD=NONE 不算加密', () {
      const String text = '''
#EXTM3U
#EXT-X-KEY:METHOD=NONE
#EXTINF:8.0,
seg.ts
''';
      final HlsPlaylist p = parsePlaylist(text, Uri.parse('https://x.com/i.m3u8'));
      expect(p.encrypted, isFalse);
    });
  });

  test('空文本 / 无扩展标签不抛异常', () {
    final HlsPlaylist empty = parsePlaylist('', Uri.parse('https://x.com/i.m3u8'));
    expect(empty.isMaster, isFalse);
    expect(empty.segments, isEmpty);

    final HlsPlaylist plain = parsePlaylist('just-a-line.ts\n', Uri.parse('https://x.com/i.m3u8'));
    expect(plain.segments.single.toString(), 'https://x.com/just-a-line.ts');
  });
}
