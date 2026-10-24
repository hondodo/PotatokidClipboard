import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pscreen_home/core/di/get_it.dart';
import 'package:pscreen_home/core/wallpaper/wallpaper_controller.dart';
import 'package:pscreen_home/features/screen/application/clock_formatter.dart';
import 'package:pscreen_screen/features/weather/application/bloc/weather_bloc.dart';
import 'package:pscreen_screen/features/weather/application/bloc/weather_state.dart';
import 'package:pscreen_screen/features/weather/data/weather_data_convert.dart';
import 'package:pscreen_screen/features/weather/domain/models/weather_models.dart';

/// 时钟页（兼屏保）。
///
/// 全屏无 AppBar、深色背景、大字号：作为中控屏的「屏保」使用。
/// 由全局屏保定时器自动进入，主页右上角的时钟入口仍可手动进入。
/// 点击画面任意位置返回上一页；不显示左上角返回按钮。
///
/// 时间、日期、农历、实时天气与未来两天预报放在同一屏：外层 [FittedBox]
/// 在屏幕过小时整体等比缩小，避免滚动或溢出。
class ClockPage extends StatefulWidget {
  const ClockPage({super.key, this.wallpaperController});

  /// 测试可注入；正式运行时为空，从全局 DI 获取。
  final WallpaperController? wallpaperController;

  @override
  State<ClockPage> createState() => _ClockPageState();
}

class _ClockPageState extends State<ClockPage> {
  DateTime _now = DateTime.now();
  Timer? _ticker;
  WallpaperController? _wallpaper;
  String? _wallpaperUrl;
  Timer? _wallpaperTimer;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
    });
    _wallpaper =
        widget.wallpaperController ??
        (getIt.isRegistered<WallpaperController>()
            ? getIt<WallpaperController>()
            : null);
    _wallpaper?.addListener(_onWallpaperChanged);
    if (_wallpaper?.enabled ?? false) {
      _wallpaperUrl = _wallpaper!.nextImageUrl();
      _restartWallpaperTimer();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _wallpaperTimer?.cancel();
    _wallpaper?.removeListener(_onWallpaperChanged);
    super.dispose();
  }

  /// 设置页修改壁纸开关 / API / 间隔后立即同步当前页面。
  void _onWallpaperChanged() {
    final WallpaperController? wallpaper = _wallpaper;
    if (!mounted || wallpaper == null) return;
    if (!wallpaper.enabled) {
      _wallpaperTimer?.cancel();
      _wallpaperTimer = null;
      if (_wallpaperUrl != null) {
        setState(() => _wallpaperUrl = null);
      }
      return;
    }
    setState(() => _wallpaperUrl = wallpaper.nextImageUrl());
    _restartWallpaperTimer();
  }

  /// 每次换图都重置计时器：手动点击「换一张」后重新计满一个间隔。
  void _restartWallpaperTimer() {
    _wallpaperTimer?.cancel();
    _wallpaperTimer = null;
    final WallpaperController? wallpaper = _wallpaper;
    if (wallpaper == null || !wallpaper.enabled) return;
    _wallpaperTimer = Timer(
      Duration(minutes: wallpaper.minutes),
      _refreshWallpaper,
    );
  }

  /// 换一张壁纸；若壁纸被关闭，则先重新开启（由监听器装载新图）。
  void _refreshWallpaper() {
    final WallpaperController? wallpaper = _wallpaper;
    if (wallpaper == null) return;
    if (!wallpaper.enabled) {
      unawaited(wallpaper.setEnabled(true));
      return;
    }
    setState(() => _wallpaperUrl = wallpaper.nextImageUrl());
    _restartWallpaperTimer();
  }

  /// 关闭壁纸：隐藏背景、停止计时并持久化开关。
  void _hideWallpaper() {
    final WallpaperController? wallpaper = _wallpaper;
    if (wallpaper == null) return;
    _wallpaperTimer?.cancel();
    _wallpaperTimer = null;
    setState(() => _wallpaperUrl = null);
    unawaited(wallpaper.setEnabled(false));
  }

  /// 按屏幕物理宽度解码，避免 4K 原图占满内存。
  int? _wallpaperCacheWidth(BuildContext context) {
    final double width = MediaQuery.sizeOf(context).width;
    final double dpr = MediaQuery.devicePixelRatioOf(context);
    final int pixels = (width * dpr).round();
    return pixels > 0 ? pixels : null;
  }

  @override
  Widget build(BuildContext context) {
    final String lunar = formatLunarLine(_now);
    final bool showWallpaper =
        (_wallpaper?.enabled ?? false) && _wallpaperUrl != null;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          if (showWallpaper) ...<Widget>[
            Positioned.fill(
              child: Image.network(
                _wallpaperUrl!,
                key: const ValueKey<String>('clock-wallpaper'),
                fit: BoxFit.cover,
                alignment: Alignment.center,
                gaplessPlayback: true,
                filterQuality: FilterQuality.medium,
                cacheWidth: _wallpaperCacheWidth(context),
                frameBuilder:
                    (
                      BuildContext context,
                      Widget child,
                      int? frame,
                      bool wasSynchronouslyLoaded,
                    ) {
                      if (wasSynchronouslyLoaded) return child;
                      return AnimatedOpacity(
                        opacity: frame == null ? 0 : 1,
                        duration: const Duration(milliseconds: 700),
                        curve: Curves.easeOut,
                        child: child,
                      );
                    },
                errorBuilder:
                    (
                      BuildContext context,
                      Object error,
                      StackTrace? stackTrace,
                    ) => const SizedBox.shrink(),
              ),
            ),
            // 压暗背景，保证白色时钟与灰色天气在亮色风景图上仍可读。
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      Color(0xB3000000),
                      Color(0x80000000),
                      Color(0xB3000000),
                    ],
                    stops: <double>[0.0, 0.5, 1.0],
                  ),
                ),
              ),
            ),
          ],
          GestureDetector(
            key: const ValueKey<String>('clock-surface'),
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).maybePop(),
            child: SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 24,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        formatClockTime(_now),
                        style: const TextStyle(
                          fontSize: 160,
                          fontWeight: FontWeight.w300,
                          color: Colors.white,
                          height: 1.0,
                          // 数字等宽：1 / 8 等字形宽度一致，秒数跳动时不抖动。
                          fontFeatures: <FontFeature>[
                            FontFeature.tabularFigures(),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        formatClockDate(_now),
                        style: const TextStyle(
                          fontSize: 40,
                          color: Colors.white70,
                        ),
                      ),
                      if (lunar.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 12),
                        Text(
                          lunar,
                          style: const TextStyle(
                            fontSize: 32,
                            color: Colors.white54,
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      _WeatherSummary(now: _now),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_wallpaper != null)
            Positioned(
              left: 20,
              bottom: 20,
              child: SafeArea(
                top: false,
                right: false,
                child: _WallpaperControls(
                  enabled: _wallpaper!.enabled,
                  onRefresh: _refreshWallpaper,
                  onHide: _hideWallpaper,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 屏保左下角的壁纸操作：换一张 / 开启 / 关闭。
class _WallpaperControls extends StatelessWidget {
  const _WallpaperControls({
    required this.enabled,
    required this.onRefresh,
    required this.onHide,
  });

  final bool enabled;
  final VoidCallback onRefresh;
  final VoidCallback onHide;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _WallpaperButton(
          icon: enabled ? Icons.refresh_rounded : Icons.wallpaper_rounded,
          label: enabled ? '换一张' : '开启壁纸',
          onPressed: onRefresh,
        ),
        if (enabled) ...<Widget>[
          const SizedBox(width: 8),
          _WallpaperButton(
            icon: Icons.visibility_off_rounded,
            label: '关闭壁纸',
            onPressed: onHide,
          ),
        ],
      ],
    );
  }
}

class _WallpaperButton extends StatelessWidget {
  const _WallpaperButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      label: Text(label),
      style: TextButton.styleFrom(
        foregroundColor: Colors.white70,
        backgroundColor: const Color(0x73000000),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
    );
  }
}

/// 天气区块：实时天气 + 今日预报 + 未来两天预报。
///
/// 实时行：城市、当前天气图标、天气与温度、今日天气图标、今日天气与
/// 温度区间；下一行：未来两天的日期 / 图标 / 天气 / 温度区间。
/// 数据缺失时对应部分静默隐藏。
class _WeatherSummary extends StatelessWidget {
  const _WeatherSummary({required this.now});

  final DateTime now;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WeatherBloc, WeatherState>(
      builder: (BuildContext context, WeatherState state) {
        final WeatherData? data = state.data;
        final WeatherNow? weatherNow = data?.now;
        if (data == null || weatherNow == null) {
          return const SizedBox.shrink();
        }

        final List<WeatherDay> daily = data.daily;
        final String todayKey = _dateKey(now);
        final int todayIndex = daily.indexWhere(
          (WeatherDay day) => day.date == todayKey,
        );
        // 接口按日期升序返回；找不到今天时按「首项是今天」兼容。
        final WeatherDay? today = todayIndex >= 0
            ? daily[todayIndex]
            : (daily.isEmpty ? null : daily.first);
        final List<WeatherDay> nextDays = daily
            .skip((todayIndex >= 0 ? todayIndex : 0) + 1)
            .take(2)
            .toList(growable: false);

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _CurrentWeatherRow(now: weatherNow, today: today),
            if (nextDays.isNotEmpty) ...<Widget>[
              const SizedBox(height: 14),
              _NextDaysRow(days: nextDays, todayKey: todayKey),
            ],
          ],
        );
      },
    );
  }
}

/// 实时天气行：城市 / 当前图标 / 当前天气 / 今日预报。
class _CurrentWeatherRow extends StatelessWidget {
  const _CurrentWeatherRow({required this.now, required this.today});

  final WeatherNow now;
  final WeatherDay? today;

  @override
  Widget build(BuildContext context) {
    final String temperature = '${now.temperature?.round() ?? '--'}°';
    final WeatherDay? todayForecast = today;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        if (now.city.isNotEmpty) ...<Widget>[
          Text(
            now.city,
            style: const TextStyle(fontSize: 28, color: Colors.white38),
          ),
          const SizedBox(width: 14),
        ],
        WeatherDataConvert.weatherIcon(context, now.skycon, size: 44),
        if (now.skycon.isNotEmpty) const SizedBox(width: 8),
        Text(
          '${now.text} $temperature',
          style: const TextStyle(fontSize: 28, color: Colors.white54),
        ),
        if (todayForecast != null) ...<Widget>[
          const SizedBox(width: 28),
          WeatherDataConvert.weatherIcon(
            context,
            todayForecast.skycon,
            size: 36,
          ),
          if (todayForecast.skycon.isNotEmpty) const SizedBox(width: 8),
          Text(
            '${todayForecast.text} ${_temperatureRange(todayForecast)}',
            style: const TextStyle(fontSize: 24, color: Colors.white38),
          ),
        ],
      ],
    );
  }
}

/// 未来两天预报行：周X / 图标 / 天气 / 温度区间。
class _NextDaysRow extends StatelessWidget {
  const _NextDaysRow({required this.days, required this.todayKey});

  final List<WeatherDay> days;
  final String todayKey;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int i = 0; i < days.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(width: 48),
          Text(
            _dayLabel(days[i]),
            style: const TextStyle(fontSize: 24, color: Colors.white54),
          ),
          const SizedBox(width: 10),
          WeatherDataConvert.weatherIcon(context, days[i].skycon, size: 30),
          if (days[i].skycon.isNotEmpty) const SizedBox(width: 8),
          Text(
            '${days[i].text} ${_temperatureRange(days[i])}',
            style: const TextStyle(fontSize: 22, color: Colors.white38),
          ),
        ],
      ],
    );
  }

  String _dayLabel(WeatherDay day) {
    final String label = WeatherDataConvert.dayLabel(day.date, todayKey);
    return label.isEmpty ? day.date : label;
  }
}

String _temperatureRange(WeatherDay day) {
  return '${day.tempMin?.round() ?? '--'}° ~ '
      '${day.tempMax?.round() ?? '--'}°';
}

String _dateKey(DateTime value) {
  return '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
