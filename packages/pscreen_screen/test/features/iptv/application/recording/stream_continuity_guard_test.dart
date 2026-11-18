import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_screen/features/iptv/application/recording/stream_continuity_guard.dart';

/// 构造一个仅含 adaptation field 的 188B TS 包，带 PCR base。
Uint8List _tsWithPcr(int pcrBase) {
  final Uint8List b = Uint8List(TsPcr.packetSize);
  b[0] = TsPcr.syncByte;
  b[1] = 0x41; // PID 0x100 + payload_unit_start
  b[2] = 0x00;
  b[3] = 0x20; // AF only, CC=0
  b[4] = 7; // AF length
  b[5] = 0x10; // PCR flag
  b[6] = (pcrBase >> 25) & 0xff;
  b[7] = (pcrBase >> 17) & 0xff;
  b[8] = (pcrBase >> 9) & 0xff;
  b[9] = (pcrBase >> 1) & 0xff;
  b[10] = ((pcrBase & 1) << 7) & 0xff;
  return b;
}

Uint8List _tsNoPcr() {
  final Uint8List b = Uint8List(TsPcr.packetSize);
  b[0] = TsPcr.syncByte;
  b[1] = 0x41;
  b[2] = 0x00;
  b[3] = 0x10; // payload only, no AF
  return b;
}

void main() {
  group('TsPcr.firstPcr', () {
    test('解析 188B 分片中的 PCR base', () {
      final int pcr = 90000 * 120 + 45000;
      expect(TsPcr.firstPcr(_tsWithPcr(pcr)), pcr);
    });

    test('无 PCR 的 TS 包返回 null', () {
      expect(TsPcr.firstPcr(_tsNoPcr()), isNull);
    });

    test('非 188 倍数的杂散字节不误读', () {
      expect(TsPcr.firstPcr(Uint8List(100)), isNull);
    });

    test('ticksPerSecond / toSeconds 正确', () {
      expect(TsPcr.toSeconds(90000), 1.0);
    });
  });

  group('SegmentQualityGate', () {
    test('相同字节分片判为重复，不写入', () {
      final SegmentQualityGate gate = SegmentQualityGate();
      final Uint8List seg = _tsWithPcr(90000);
      expect(gate.evaluate(seg).write, isTrue);
      final GateDecision second = gate.evaluate(Uint8List.fromList(seg));
      expect(second.write, isFalse);
      expect(second.reason, 'duplicate');
    });

    test('PCR 正常递增不触发归零', () {
      final SegmentQualityGate gate = SegmentQualityGate();
      gate.evaluate(_tsWithPcr(90000 * 10));
      final GateDecision next = gate.evaluate(_tsWithPcr(90000 * 12));
      expect(next.write, isTrue);
      expect(next.pcrReset, isFalse);
    });

    test('PCR 大幅倒退（会话归零）触发 pcrReset 且仍写入', () {
      final SegmentQualityGate gate = SegmentQualityGate();
      gate.evaluate(_tsWithPcr(90000 * 1201));
      final GateDecision next = gate.evaluate(_tsWithPcr(90000 * 1));
      expect(next.write, isTrue);
      expect(next.pcrReset, isTrue);
      expect(next.reason, contains('pcr-reset'));
    });

    test('小范围倒退（<=阈值）不误判会话归零', () {
      final SegmentQualityGate gate = SegmentQualityGate();
      gate.evaluate(_tsWithPcr(90000 * 100));
      final GateDecision next = gate.evaluate(_tsWithPcr(90000 * 98));
      expect(next.pcrReset, isFalse);
    });

    test('reset 后重新建立基准', () {
      final SegmentQualityGate gate = SegmentQualityGate();
      gate.evaluate(_tsWithPcr(90000 * 100));
      gate.reset();
      final GateDecision next = gate.evaluate(_tsWithPcr(90000 * 1));
      expect(next.pcrReset, isFalse);
      expect(next.write, isTrue);
    });
  });
}
