import 'package:flutter/material.dart';
import 'package:potatokid_clipboard/framework/theme/app_text_theme.dart';

class AppTheme {
  static final AppTheme _instance = AppTheme._();
  static AppTheme get instance => _instance;

  AppTheme._();

  AppTextTheme get textTheme => AppTextTheme.instance;

  Color get pageBgColor => Colors.white;
  Color get primaryColor => Colors.blue;
}
