/// HLS 播放列表的纯解析器（无 IO、无 Flutter 依赖，便于单测）。
///
/// 只解析录制需要的字段：
/// - master playlist：取 `#EXT-X-STREAM-INF` 的带宽与下一行 URL，供选最低码率；
/// - media playlist：取 `EXT-X-MEDIA-SEQUENCE` / 分片行；
/// - 检测 `#EXT-X-KEY`：加密流本期直接拒绝录制。
///
/// 本文件不下载任何分片，也不写文件；那部分在 recording_controller。
library;

/// master playlist 中的一个码率分支。
class HlsVariant {
  const HlsVariant({
    required this.url,
    this.bandwidth,
  });

  /// 分支 URL（已按 base resolve 成绝对地址）。
  final Uri url;

  /// `BANDWIDTH` 属性值；缺失时为 null，排序时视为无穷大。
  final int? bandwidth;

  @override
  String toString() => 'HlsVariant(bandwidth: $bandwidth, url: $url)';
}

/// [parsePlaylist] 的解析结果。
class HlsPlaylist {
  const HlsPlaylist({
    required this.base,
    required this.isMaster,
    this.variants = const <HlsVariant>[],
    this.segments = const <Uri>[],
    this.mediaSequence = 0,
    this.targetDuration = 0,
    this.encrypted = false,
  });

  /// 解析时传入的基准 URI（master 或 media playlist 的地址）。
  final Uri base;

  /// 是否为 master playlist（含 `EXT-X-STREAM-INF`）。
  final bool isMaster;

  /// master 的分支列表（仅 isMaster 时非空）。
  final List<HlsVariant> variants;

  /// media 的分片 URL 列表（仅非 master 时非空），均为绝对地址。
  final List<Uri> segments;

  /// `EXT-X-MEDIA-SEQUENCE`，缺省 0。
  final int mediaSequence;

  /// `EXT-X-TARGETDURATION`（秒），缺省 0。
  final int targetDuration;

  /// 是否出现 `#EXT-X-KEY`（AES-128 等）。加密流本期不支持录制。
  final bool encrypted;

  /// 选出带宽最低的分支 URL；无分支（media playlist 或空 master）时返回 base。
  ///
  /// 录制只拉最低码率分支以省带宽（方案 D-1）。bandwidth 缺失视为无穷大，
  /// 全部缺失时退回第一个分支。
  Uri get selectedVariantUrl {
    if (variants.isEmpty) return base;
    int bestIndex = 0;
    int? bestBw = variants.first.bandwidth;
    for (int i = 1; i < variants.length; i++) {
      final int? bw = variants[i].bandwidth;
      if (bestBw == null) {
        // 当前最优无带宽：仅当候选有带宽时才替换；全无带宽保留第一个。
        if (bw != null) {
          bestIndex = i;
          bestBw = bw;
        }
      } else if (bw != null && bw < bestBw) {
        bestIndex = i;
        bestBw = bw;
      }
    }
    return variants[bestIndex].url;
  }
}

/// 解析 HLS playlist 文本。
///
/// [base] 用于把相对 URL resolve 成绝对地址。[text] 为 m3u8 原文。
/// 解析容错：无法识别的数字按缺省值处理，不抛异常（直播源质量参差）。
HlsPlaylist parsePlaylist(String text, Uri base) {
  final List<String> lines = text.split(RegExp(r'\r?\n'));

  bool isMaster = false;
  final List<HlsVariant> variants = <HlsVariant>[];
  final List<Uri> segments = <Uri>[];
  int mediaSequence = 0;
  int targetDuration = 0;
  bool encrypted = false;

  // master 里 `#EXT-X-STREAM-INF` 之后紧跟的一行是分支 URL；bandwidth 可缺省。
  bool expectVariantUrl = false;
  int? pendingBandwidth;

  for (final String raw in lines) {
    final String line = raw.trim();
    if (line.isEmpty) continue;

    if (line.startsWith('#')) {
      final String upper = line.toUpperCase();
      if (upper.startsWith('#EXT-X-STREAM-INF')) {
        isMaster = true;
        expectVariantUrl = true;
        pendingBandwidth = _attributeInt(line, 'BANDWIDTH');
      } else if (upper.startsWith('#EXT-X-MEDIA-SEQUENCE')) {
        mediaSequence = _trailingInt(line) ?? mediaSequence;
      } else if (upper.startsWith('#EXT-X-TARGETDURATION')) {
        targetDuration = _trailingInt(line) ?? targetDuration;
      } else if (upper.startsWith('#EXT-X-KEY')) {
        // METHOD=NONE 表示显式关闭加密，不算加密。
        final String? method = _attribute(line, 'METHOD');
        if (method != null && method.toUpperCase() != 'NONE') {
          encrypted = true;
        }
      }
      continue;
    }

    // 非注释行 = URL。
    final Uri resolved = base.resolve(line);
    if (expectVariantUrl) {
      variants.add(HlsVariant(url: resolved, bandwidth: pendingBandwidth));
      expectVariantUrl = false;
      pendingBandwidth = null;
    } else if (isMaster) {
      // master 里孤立的 URL 行（无前置 STREAM-INF）不识别，忽略。
      continue;
    } else {
      // media playlist 中非注释行即分片 URL（BYTE RANGE 本期忽略）。
      segments.add(resolved);
    }
  }

  return HlsPlaylist(
    base: base,
    isMaster: isMaster,
    variants: List<HlsVariant>.unmodifiable(variants),
    segments: List<Uri>.unmodifiable(segments),
    mediaSequence: mediaSequence,
    targetDuration: targetDuration,
    encrypted: encrypted,
  );
}

/// 从属性列表行（如 `#EXT-X-STREAM-INF:BANDWIDTH=800000,CODECS="..."`）取字符串属性。
String? _attribute(String line, String key) {
  final int colon = line.indexOf(':');
  if (colon < 0) return null;
  final String attrs = line.substring(colon + 1);
  for (final String part in attrs.split(',')) {
    final int eq = part.indexOf('=');
    if (eq < 0) continue;
    if (part.substring(0, eq).trim().toUpperCase() == key.toUpperCase()) {
      return part.substring(eq + 1).trim().replaceAll('"', '');
    }
  }
  return null;
}

int? _attributeInt(String line, String key) => int.tryParse(_attribute(line, key) ?? '');

/// 取 `KEY:VALUE` 形式行末尾的整数（如 `#EXT-X-MEDIA-SEQUENCE:42`）。
int? _trailingInt(String line) {
  final int colon = line.lastIndexOf(':');
  if (colon < 0) return null;
  return int.tryParse(line.substring(colon + 1).trim());
}
