/// 家长端 V4 设计系统 Token（与 docs/parent-app-ui-design-system.md 一致）。
///
/// 通过 `ThemeExtension` 注入，页面用 `ParentalTheme.of(context)` 取用。
/// 浅色为主（家长 App 固定浅色），深色同步映射（不是简单取反）。
///
/// 设计基线来源：docs/parent-app-redesign-prototype-v4.html 与
/// docs/parent-app-ui-design-system.md。所有文字组合 ≥ WCAG AA 4.5:1。
library;

import 'package:flutter/material.dart';

/// 文字层级（1.25 比例，基于 16px）。
enum ParentalTextRole {
  display, // 32/40 700 关键数据（剩余分钟）
  h1, // 26/34 700 页面大标题
  h2, // 22/30 650 弹层标题 / 区块主标题
  h3, // 18/26 650 卡片主标题 / 姓名
  bodyLg, // 16/24 400 正文重点
  body, // 14/22 400 正文（最小正文）
  label, // 13/18 500 表单标签 / 区块标题
  caption, // 12/16 500 仅辅助标签
}

class ParentalTheme extends ThemeExtension<ParentalTheme> {
  const ParentalTheme._({
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.ink,
    required this.ink2,
    required this.ink3,
    required this.line,
    required this.lineStrong,
    required this.brand,
    required this.brandStrong,
    required this.brandSoft,
    required this.brandOn,
    required this.warn,
    required this.warnSoft,
    required this.danger,
    required this.dangerSoft,
    required this.info,
    required this.infoSoft,
  });

  // —— 颜色 ——
  final Color bg;
  final Color surface;
  final Color surface2;
  final Color ink;
  final Color ink2;
  final Color ink3;
  final Color line;
  final Color lineStrong;
  final Color brand;
  final Color brandStrong;
  final Color brandSoft;
  final Color brandOn;
  final Color warn;
  final Color warnSoft;
  final Color danger;
  final Color dangerSoft;
  final Color info;
  final Color infoSoft;

  /// 浅色主题（家长 App 默认）。
  static const ParentalTheme light = ParentalTheme._(
    bg: Color(0xFFF5F8F6),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFEDF3EF),
    ink: Color(0xFF16211D),
    ink2: Color(0xFF4A5A53),
    ink3: Color(0xFF5B6B63),
    line: Color(0xFFDCE5E0),
    lineStrong: Color(0xFFB9C9C0),
    brand: Color(0xFF0F7A5F),
    brandStrong: Color(0xFF0B6249),
    brandSoft: Color(0xFFE8F5EF),
    brandOn: Color(0xFFFFFFFF),
    warn: Color(0xFF8A5200),
    warnSoft: Color(0xFFFFF3DC),
    danger: Color(0xFFB3261E),
    dangerSoft: Color(0xFFFDEDEC),
    info: Color(0xFF1B5E8A),
    infoSoft: Color(0xFFE7F1F8),
  );

  /// 深色主题（品牌绿提亮以维持 8.76:1，危险色低饱和亮红）。
  static const ParentalTheme dark = ParentalTheme._(
    bg: Color(0xFF0F1714),
    surface: Color(0xFF17231E),
    surface2: Color(0xFF1E2E27),
    ink: Color(0xFFEAF2EE),
    ink2: Color(0xFFA9BDB4),
    ink3: Color(0xFF8EA39A),
    line: Color(0xFF2C3B34),
    lineStrong: Color(0xFF40564B),
    brand: Color(0xFF5FD3A6),
    brandStrong: Color(0xFF7FE0BA),
    brandSoft: Color(0xFF17382C),
    brandOn: Color(0xFF06251B),
    warn: Color(0xFFF0B866),
    warnSoft: Color(0xFF3A2A12),
    danger: Color(0xFFFF9E94),
    dangerSoft: Color(0xFF3A1A17),
    info: Color(0xFF8CC7EC),
    infoSoft: Color(0xFF162A38),
  );

  /// 从 [Brightness] 取对应主题。
  static ParentalTheme ofBrightness(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  /// 便捷取用：从 [BuildContext] 读取注入的扩展。
  static ParentalTheme of(BuildContext context) =>
      Theme.of(context).extension<ParentalTheme>() ?? light;

  // —— 间距（4pt base / 8pt rhythm）——
  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 12;
  static const double s4 = 16;
  static const double s5 = 20;
  static const double s6 = 24;
  static const double s8 = 32;
  static const double s10 = 40;
  static const double s12 = 48;
  static const double s16 = 64;

  // —— 圆角 ——
  static const double rSm = 8;
  static const double rMd = 12;
  static const double rLg = 16;
  static const double rXl = 20;
  static const double rPill = 999;

  // —— 阴影（统一缓动 reserved）——
  static List<BoxShadow> get elevation1 => const [
    BoxShadow(color: Color(0x0F10281E), blurRadius: 2, offset: Offset(0, 1)),
  ];
  static List<BoxShadow> get elevation2 => const [
    BoxShadow(color: Color(0x1410281E), blurRadius: 12, offset: Offset(0, 4)),
  ];
  static List<BoxShadow> get elevation3 => const [
    BoxShadow(color: Color(0x2410281E), blurRadius: 32, offset: Offset(0, 12)),
  ];

  // —— 动效 ——
  static const Duration mFast = Duration(milliseconds: 150);
  static const Duration mBase = Duration(milliseconds: 240);
  static const Duration mSlow = Duration(milliseconds: 400);
  static const Cubic ease = Cubic(0.2, 0.8, 0.2, 1);

  /// 统一字体栈（含中文回退）；数字启用 tabular-nums 防止时长跳动。
  static const String fontFamilyFallback =
      '-apple-system, BlinkMacSystemFont, "Segoe UI", "PingFang SC", "Microsoft YaHei", sans-serif';

  TextStyle text(ParentalTextRole role, {Color? color, FontWeight? weight}) {
    const FontWeight w700 = FontWeight.w700;
    const FontWeight w650 = FontWeight.w600;
    const FontWeight w500 = FontWeight.w500;
    const FontWeight w400 = FontWeight.w400;
    late final double size;
    late final double height;
    late final FontWeight weight0;
    switch (role) {
      case ParentalTextRole.display:
        size = 32; height = 40; weight0 = w700;
      case ParentalTextRole.h1:
        size = 26; height = 34; weight0 = w700;
      case ParentalTextRole.h2:
        size = 22; height = 30; weight0 = w650;
      case ParentalTextRole.h3:
        size = 18; height = 26; weight0 = w650;
      case ParentalTextRole.bodyLg:
        size = 16; height = 24; weight0 = w400;
      case ParentalTextRole.body:
        size = 14; height = 22; weight0 = w400;
      case ParentalTextRole.label:
        size = 13; height = 18; weight0 = w500;
      case ParentalTextRole.caption:
        size = 12; height = 16; weight0 = w500;
    }
    return TextStyle(
      fontSize: size,
      height: height / size,
      fontWeight: weight ?? weight0,
      color: color,
      fontFamilyFallback: const ['PingFang SC', 'Microsoft YaHei', 'sans-serif'],
    );
  }

  @override
  ParentalTheme copyWith({
    Color? bg,
    Color? surface,
    Color? surface2,
    Color? ink,
    Color? ink2,
    Color? ink3,
    Color? line,
    Color? lineStrong,
    Color? brand,
    Color? brandStrong,
    Color? brandSoft,
    Color? brandOn,
    Color? warn,
    Color? warnSoft,
    Color? danger,
    Color? dangerSoft,
    Color? info,
    Color? infoSoft,
  }) =>
      ParentalTheme._(
        bg: bg ?? this.bg,
        surface: surface ?? this.surface,
        surface2: surface2 ?? this.surface2,
        ink: ink ?? this.ink,
        ink2: ink2 ?? this.ink2,
        ink3: ink3 ?? this.ink3,
        line: line ?? this.line,
        lineStrong: lineStrong ?? this.lineStrong,
        brand: brand ?? this.brand,
        brandStrong: brandStrong ?? this.brandStrong,
        brandSoft: brandSoft ?? this.brandSoft,
        brandOn: brandOn ?? this.brandOn,
        warn: warn ?? this.warn,
        warnSoft: warnSoft ?? this.warnSoft,
        danger: danger ?? this.danger,
        dangerSoft: dangerSoft ?? this.dangerSoft,
        info: info ?? this.info,
        infoSoft: infoSoft ?? this.infoSoft,
      );

  @override
  ParentalTheme lerp(ThemeExtension<ParentalTheme>? other, double t) {
    if (other is! ParentalTheme) return this;
    return ParentalTheme._(
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surface2: Color.lerp(surface2, other.surface2, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      ink2: Color.lerp(ink2, other.ink2, t)!,
      ink3: Color.lerp(ink3, other.ink3, t)!,
      line: Color.lerp(line, other.line, t)!,
      lineStrong: Color.lerp(lineStrong, other.lineStrong, t)!,
      brand: Color.lerp(brand, other.brand, t)!,
      brandStrong: Color.lerp(brandStrong, other.brandStrong, t)!,
      brandSoft: Color.lerp(brandSoft, other.brandSoft, t)!,
      brandOn: Color.lerp(brandOn, other.brandOn, t)!,
      warn: Color.lerp(warn, other.warn, t)!,
      warnSoft: Color.lerp(warnSoft, other.warnSoft, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerSoft: Color.lerp(dangerSoft, other.dangerSoft, t)!,
      info: Color.lerp(info, other.info, t)!,
      infoSoft: Color.lerp(infoSoft, other.infoSoft, t)!,
    );
  }
}
