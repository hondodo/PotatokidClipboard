import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:potatokid_screen/features/weather/presentation/widgets/weather_panel.dart';

/// 「屏保」Tab 占位页：后续在此实现屏保相关功能。
class ScreensaverPage extends StatelessWidget {
  const ScreensaverPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.wallpaper_outlined,
                size: 64,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text('screensaver_title'.tr(), style: theme.textTheme.headlineSmall),
            ],
          ),
        ),
        // 天气小组件：右上角悬浮，无数据时自动隐藏。
        const Positioned(
          top: 12,
          right: 12,
          child: SafeArea(child: WeatherPanel()),
        ),
      ],
    );
  }
}