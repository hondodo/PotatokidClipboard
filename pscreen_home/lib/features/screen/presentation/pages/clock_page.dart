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
/// 触屏交互：点击画面切换秒显示；左上角返回箭头回到中控台。
class ClockPage extends StatefulWidget {
  const ClockPage({super.key});

  @override
  State<ClockPage> createState() => _ClockPageState();
}

class _ClockPageState extends State<ClockPage> {
  DateTime _now = DateTime.now();
  bool _showSeconds = true;
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

  void _toggleSeconds() {
    setState(() => _showSeconds = !_showSeconds);
  }

  @override
  Widget build(BuildContext context) {
    final String lunar = formatLunarLine(_now);
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        key: const ValueKey<String>('clock-surface'),
        onTap: _toggleSeconds,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          children: <Widget>[
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(
                    formatClockTime(_now, withSeconds: _showSeconds),
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
                    style: const TextStyle(fontSize: 40, color: Colors.white70),
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
                  const SizedBox(height: 32),
                  const _WeatherSummary(),
                ],
              ),
            ),
            Positioned(
              top: 24,
              left: 24,
              child: IconButton(
                tooltip: '返回',
                icon: const Icon(
                  Icons.arrow_back_rounded,
                  color: Colors.white70,
                ),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
          ],
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
        return Text(
          text,
          style: const TextStyle(fontSize: 28, color: Colors.white38),
        );
      },
    );
  }
}
