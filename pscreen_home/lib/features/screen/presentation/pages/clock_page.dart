import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pscreen_home/features/screen/application/clock_formatter.dart';
import 'package:pscreen_screen/features/weather/application/bloc/weather_bloc.dart';
import 'package:pscreen_screen/features/weather/application/bloc/weather_state.dart';
import 'package:pscreen_screen/features/weather/domain/models/weather_models.dart';

/// 时钟页（兼屏保）。
///
/// 全屏无 AppBar、深色背景、大字号：作为中控屏的「屏保」使用。
/// 由全局屏保定时器自动进入，主页右上角的时钟入口仍可手动进入。
/// 点击画面任意位置返回上一页；不显示左上角返回按钮。
class ClockPage extends StatefulWidget {
  const ClockPage({super.key});

  @override
  State<ClockPage> createState() => _ClockPageState();
}

class _ClockPageState extends State<ClockPage> {
  DateTime _now = DateTime.now();
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String lunar = formatLunarLine(_now);
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        key: const ValueKey<String>('clock-surface'),
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).maybePop(),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                formatClockTime(_now),
                style: const TextStyle(
                  fontSize: 160,
                  fontWeight: FontWeight.w300,
                  color: Colors.white,
                  height: 1.0,
                  // 数字等宽：1 / 8 等字形宽度一致，秒数跳动时不抖动。
                  fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 24),
              Text(formatClockDate(_now), style: const TextStyle(fontSize: 40, color: Colors.white70)),
              if (lunar.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                Text(lunar, style: const TextStyle(fontSize: 32, color: Colors.white54)),
              ],
              const SizedBox(height: 32),
              const _WeatherSummary(),
            ],
          ),
        ),
      ),
    );
  }
}

/// 天气摘要：取共享包 WeatherBloc 的实时天气（无数据时静默隐藏）。
class _WeatherSummary extends StatelessWidget {
  const _WeatherSummary();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WeatherBloc, WeatherState>(
      builder: (BuildContext context, WeatherState state) {
        final WeatherNow? now = state.data?.now;
        if (now == null) return const SizedBox.shrink();
        final String text =
            '${now.city.isEmpty ? '' : '${now.city} · '}'
            '${now.text} ${now.temperature?.round() ?? ''}°';
        return Text(text, style: const TextStyle(fontSize: 28, color: Colors.white38));
      },
    );
  }
}
