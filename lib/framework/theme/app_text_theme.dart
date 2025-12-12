import 'package:flutter/material.dart';

class AppTextTheme {
  static final AppTextTheme _instance = AppTextTheme._();
  static AppTextTheme get instance => _instance;

  AppTextTheme._();

  /// 最小字体大小 10px
  static const double fontSizeMini = 10.0;

  /// 小字体大小 12px
  static const double fontSizeSmall = 12.0;

  /// 中字体大小 14px
  static const double fontSizeMedium = 14.0;

  /// 大字体大小 16px
  static const double fontSizeLarge = 16.0;

  /// 特大字体大小 18px
  static const double fontSizeXLarge = 18.0;

  /// 超大字体大小 20px
  static const double fontSizeXXLarge = 20.0;

  /// 特超大字体大小 22px
  static const double fontSizeXXXLarge = 22.0;

  /// 超大字体大小 24px
  static const double fontSizeXXXXLarge = 24.0;

  /// 特超大字体大小 26px
  static const double fontSizeXXXXXLarge = 26.0;

  /// 特特超大字体大小 28px
  static const double fontSizeXXXXXXLarge = 28.0;

  /// 特特特超大字体大小 30px
  static const double fontSizeXXXXXXXLarge = 30.0;

  /// 字体粗细
  static const FontWeight fontWeightRegular = FontWeight.normal;

  /// 字体粗细（500）
  static const FontWeight fontWeightMedium = FontWeight.w500;

  /// 字体粗细（700）
  static const FontWeight fontWeightBold = FontWeight.bold;

  /// 默认文字颜色
  static const Color textColor = Colors.black;

  /// 提示文字颜色
  static const Color hintColor = Colors.grey;

  /// 禁用文字颜色（灰色，透明度38%）
  static Color disabledColor = Colors.grey.withOpacity(0.38);

  /// 按钮文字颜色
  static const Color buttonTextColor = Colors.white;

  /// 主色调颜色
  static const Color primaryColor = Colors.blue;

  /// 次色调颜色
  static const Color secondaryColor = Colors.grey;

  /// 成功颜色
  static const Color successColor = Colors.green;

  /// 错误颜色
  static const Color errorColor = Colors.red;

  /// 警告颜色
  static const Color warningColor = Colors.yellow;

  /// 信息颜色
  static const Color infoColor = Colors.blue;

  /// 浅色颜色
  static const Color lightColor = Colors.white;

  /// 深色颜色
  static const Color darkColor = Colors.black;

  /// 默认文字样式，12px，粗细为常规，颜色为黑色
  static const TextStyle textStyle =
      TextStyle(fontSize: fontSizeSmall, fontWeight: fontWeightRegular);
}

extension TextThemeExtension on TextStyle {
  TextStyle resize(double fontSize) {
    return copyWith(fontSize: fontSize);
  }

  TextStyle setColor(Color? color) {
    return copyWith(color: color);
  }

  TextStyle setWeight(FontWeight fontWeight) {
    return copyWith(fontWeight: fontWeight);
  }

  TextStyle setDecoration(TextDecoration decoration) {
    return copyWith(decoration: decoration);
  }

  TextStyle setHeight(double height) {
    return copyWith(height: height);
  }

  TextStyle get disabled => copyWith(color: AppTextTheme.disabledColor);
  TextStyle get buttonText => copyWith(color: AppTextTheme.buttonTextColor);
  TextStyle get primary => copyWith(color: AppTextTheme.primaryColor);
  TextStyle get secondary => copyWith(color: AppTextTheme.secondaryColor);
  TextStyle get success => copyWith(color: AppTextTheme.successColor);
  TextStyle get error => copyWith(color: AppTextTheme.errorColor);
  TextStyle get warning => copyWith(color: AppTextTheme.warningColor);
  TextStyle get info => copyWith(color: AppTextTheme.infoColor);

  TextStyle get regular => copyWith(fontWeight: AppTextTheme.fontWeightRegular);
  TextStyle get medium => copyWith(fontWeight: AppTextTheme.fontWeightMedium);
  TextStyle get bold => copyWith(fontWeight: AppTextTheme.fontWeightBold);

  /// 标题文字样式，16px，粗细为粗体，颜色为黑色
  TextStyle get title => copyWith(
      fontSize: AppTextTheme.fontSizeLarge,
      fontWeight: AppTextTheme.fontWeightBold);

  /// 副标题文字样式，14px，粗细为常规，颜色为黑色
  TextStyle get subtitle => copyWith(
      fontSize: AppTextTheme.fontSizeMedium,
      fontWeight: AppTextTheme.fontWeightRegular);

  /// 正文文字样式，12px，粗细为常规，颜色为黑色
  TextStyle get body => copyWith(
      fontSize: AppTextTheme.fontSizeSmall,
      fontWeight: AppTextTheme.fontWeightRegular);

  /// 提示文字样式，10px，粗细为常规，颜色为灰色
  TextStyle get hint => copyWith(
      fontSize: AppTextTheme.fontSizeMini,
      fontWeight: AppTextTheme.fontWeightRegular,
      color: AppTextTheme.hintColor);

  /// 应用栏标题文字样式，16px，粗细为粗体，颜色为白色
  TextStyle get appBarTitle => copyWith(
      fontSize: AppTextTheme.fontSizeLarge,
      fontWeight: AppTextTheme.fontWeightBold,
      color: AppTextTheme.lightColor);

  /// 应用栏副标题文字样式，14px，粗细为常规，颜色为白色
  TextStyle get appBarSubtitle => copyWith(
      fontSize: AppTextTheme.fontSizeMedium,
      fontWeight: AppTextTheme.fontWeightRegular,
      color: AppTextTheme.lightColor);

  /// 应用栏正文文字样式，12px，粗细为常规，颜色为白色
  TextStyle get appBarBody => copyWith(
      fontSize: AppTextTheme.fontSizeSmall,
      fontWeight: AppTextTheme.fontWeightRegular,
      color: AppTextTheme.lightColor);
}
