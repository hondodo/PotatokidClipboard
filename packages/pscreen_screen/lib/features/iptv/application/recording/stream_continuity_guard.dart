import 'dart:collection';

import 'package:crypto/crypto.dart';

/// MPEG-2 TS 分片时间戳解析 + 录制连续性闸门。
///
/// 背景：relay 直播在中途可能换 sid（会话重启），新会话的 PCR 从 0 重新
/// 开始；而轮询锚点丢失时又会整窗重下，写出字节完全相同的重复分片。
/// 裸拼 .ts 文件不含时间戳重映射，这些异常会原样固化成回放时的「跳帧」。
///
/// 本工具只做只读解析与判定：
/// - [TsPcr.firstPcr]：提取分片首个 PCR（90kHz tick）；
/// - [SegmentQualityGate]：重复片拦截 + 归零断崖检测，供录制写入前调用。
///
/// 纯函数、零 IO、无平台依赖，便于单测。不修改 relay、不改写流字节。
class TsPcr {
  TsPcr._();

  /// TS 包固定 188 字节，首字节同步字 0x47。
  static const int packetSize = 188;
  static const int syncByte = 0x47;

  /// PCR 基准时钟 90kHz。
  static const int ticksPerSecond = 90000;

  /// 返回分片中首个 PCR base（单位 90kHz tick）；无 PCR 返回 null。
  ///
  /// PCR base 为 33 位，跨 5 字节：
  /// b0<<25 | b1<<17 | b2<<9 | b3<<1 | b4>>7。
  /// 仅读取 adaptation_field 中 PCR flag 置位的包，不改动任何字节。
  static int? firstPcr(List<int> bytes) {
    final int count = bytes.length ~/ packetSize;
    for (int i = 0; i < count; i++) {
      final int b = i * packetSize;
      if (bytes[b] != syncByte) continue;
      // adaptation_field_control: 2=仅 AF, 3=AF+payload
      final int afc = (bytes[b + 3] >> 4) & 0x3;
      if (afc != 2 && afc != 3) continue;
      final int afLen = bytes[b + 4];
      // AF 至少含 flags(1) + PCR(6) = 7 字节，且不能越界
      if (afLen < 7 || b + 5 + afLen > bytes.length) continue;
      if ((bytes[b + 5] & 0x10) == 0) continue; // PCR flag
      final int o = b + 6;
      return (bytes[o] << 25) |
          (bytes[o + 1] << 17) |
          (bytes[o + 2] << 9) |
          (bytes[o + 3] << 1) |
          (bytes[o + 4] >> 7);
    }
    return null;
  }

  /// 90kHz tick 转秒。
  static double toSeconds(int ticks) => ticks / ticksPerSecond;
}

/// 一次分片判定结果。
class GateDecision {
  const GateDecision({
    required this.write,
    this.pcrReset = false,
    this.reason = '',
    this.pcrTicks,
  });

  /// 是否应写入文件。
  final bool write;

  /// 检测到 PCR 大幅倒退（会话归零）：写入本片后应另起新文件。
  final bool pcrReset;

  /// 诊断用原因标记。
  final String reason;

  /// 本片解析到的 PCR（90kHz tick），可能为 null。
  final int? pcrTicks;
}

/// 录制连续性闸门：去重 + 时间戳归零检测。
///
/// 用法：每个分片下载后、写入前调用 [evaluate]；
/// - [GateDecision.write]==false → 跳过（重复片）；
/// - [GateDecision.pcrReset]==true → 正常写入后另起新文件（会话归零）。
class SegmentQualityGate {
  /// 有界去重窗口。重复片实测均为相邻或近距离（间隔 0~2 片），256 足够；
  /// 有界避免数小时录制时 md5 集合无限增长。
  static const int maxRecentHashes = 256;

  /// PCR 倒退超过此秒数判定为会话归零。
  /// 正常分片间隔约 targetDuration(2~4s)；重复片倒退不超过间隔，不会误判。
  static const double pcrResetThresholdSec = 30.0;

  final LinkedHashSet<String> _recentHashes = LinkedHashSet<String>();
  int? _lastPcrTicks;

  /// 判定一个分片。
  GateDecision evaluate(List<int> bytes) {
    final String digest = md5.convert(bytes).toString();
    if (_recentHashes.contains(digest)) {
      return const GateDecision(write: false, reason: 'duplicate');
    }
    _recentHashes.add(digest);
    if (_recentHashes.length > maxRecentHashes) {
      _recentHashes.remove(_recentHashes.first);
    }

    final int? pcr = TsPcr.firstPcr(bytes);
    if (pcr == null) {
      return const GateDecision(write: true, reason: 'no-pcr');
    }
    final int? last = _lastPcrTicks;
    _lastPcrTicks = pcr;
    if (last != null) {
      final double deltaSec = (pcr - last) / TsPcr.ticksPerSecond;
      if (deltaSec < -pcrResetThresholdSec) {
        return GateDecision(
          write: true,
          pcrReset: true,
          reason: 'pcr-reset(${deltaSec.toStringAsFixed(0)}s)',
          pcrTicks: pcr,
        );
      }
    }
    return GateDecision(write: true, reason: 'ok', pcrTicks: pcr);
  }

  /// 完全重置（开新录制时调用）。
  void reset() {
    _recentHashes.clear();
    _lastPcrTicks = null;
  }
}
