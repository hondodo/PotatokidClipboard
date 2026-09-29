import 'package:flutter/widgets.dart';

/// 「画面」显示模式（「我的」页可调）：决定视频在屏幕中的铺排方式。
///
/// 组合 [fit] 与 [aspectRatio] 映射到 media_kit 的 [Video] 控件参数：
/// - 原始：按视频原始宽高比显示（原样、不拉伸）；
/// - 拉伸：填满整屏（忽略宽高比，可能纵向/横向变形）；
/// - 16:9 / 4:3 / 21:9：强制按指定宽高比显示，超出部分以黑边补齐。
enum VideoAspectMode {
  /// 原始
  original,

  /// 拉伸
  stretch,

  /// 16:9
  ratio16_9,

  /// 4:3
  ratio4_3,

  /// 21:9
  ratio21_9;

  /// 对应 [Video] 的 fit。
  BoxFit get fit => switch (this) {
        VideoAspectMode.stretch => BoxFit.fill,
        _ => BoxFit.contain,
      };

  /// 强制展示的宽高比；null 表示采用视频原始宽高。
  double? get aspectRatio => switch (this) {
        VideoAspectMode.ratio16_9 => 16 / 9,
        VideoAspectMode.ratio4_3 => 4 / 3,
        VideoAspectMode.ratio21_9 => 21 / 9,
        _ => null,
      };

  /// 翻译 key。
  String get labelKey => switch (this) {
        VideoAspectMode.original => 'video_aspect_original',
        VideoAspectMode.stretch => 'video_aspect_stretch',
        VideoAspectMode.ratio16_9 => 'video_aspect_16_9',
        VideoAspectMode.ratio4_3 => 'video_aspect_4_3',
        VideoAspectMode.ratio21_9 => 'video_aspect_21_9',
      };

  /// 从持久化名称还原；未知/空值回退到 [VideoAspectMode.original]。
  static VideoAspectMode fromName(String? name) {
    for (final VideoAspectMode m in VideoAspectMode.values) {
      if (m.name == name) return m;
    }
    return VideoAspectMode.original;
  }
}