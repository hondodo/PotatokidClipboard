import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pscreen_screen/features/weather/application/bloc/weather_bloc.dart';
import 'package:pscreen_screen/features/weather/application/bloc/weather_event.dart';
import 'package:pscreen_screen/features/weather/application/bloc/weather_state.dart';
import 'package:pscreen_screen/features/weather/data/weather_data_convert.dart';
import 'package:pscreen_screen/features/weather/domain/models/weather_models.dart';

/// 天气页：实时天气 + 未来 3 天预报（触屏版，UI 自写，数据来自共享包）。
///
/// 横屏大屏用左右两栏铺满：左侧实时天气，右侧逐日预报；窄屏则按上下
/// 布局滚动，避免小窗口溢出。日期使用「今天 / 周X」而不是原始日期串，
/// 预报项带天气图标，方便远距离扫一眼。
class WeatherPage extends StatelessWidget {
  const WeatherPage({super.key});

  /// 预报最多展示天数（心知免费版通常返回 3 天）。
  static const int _forecastDays = 3;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('天气'),
        actions: <Widget>[
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () =>
                context.read<WeatherBloc>().add(const LoadWeather()),
          ),
        ],
      ),
      body: BlocBuilder<WeatherBloc, WeatherState>(
        builder: (BuildContext context, WeatherState state) {
          if (state.isLoading && !state.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.errorMessage != null && !state.hasData) {
            return Center(
              child: Text(
                state.errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            );
          }
          if (!state.hasData) {
            return const Center(child: Text('暂无天气数据'));
          }

          final WeatherData data = state.data!;
          final WeatherDay? today = data.daily.firstOrNull;
          final List<WeatherDay> days = data.daily
              .take(_forecastDays)
              .toList(growable: false);

          return LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              // 大屏横屏：两栏铺满，所有预报一屏可见，不留大片空白。
              if (constraints.maxWidth >= 1000) {
                return Padding(
                  padding: const EdgeInsets.all(24),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Expanded(
                        flex: 5,
                        child: _NowCard(now: data.now, today: today),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        flex: 6,
                        child: _ForecastPanel(days: days, fillHeight: true),
                      ),
                    ],
                  ),
                );
              }

              // 窄屏兜底：上下排列，允许滚动，避免卡片被压扁。
              return ListView(
                padding: const EdgeInsets.all(16),
                children: <Widget>[
                  _NowCard(now: data.now, today: today),
                  const SizedBox(height: 16),
                  _ForecastPanel(days: days, fillHeight: false),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

/// 实时天气卡片。
///
/// 大屏下由父级拉伸到整列高度，用 [MainAxisAlignment.spaceEvenly] 把
/// 城市、温度、温度区间和湿度/风速均匀铺开；窄屏下自动收缩为内容高度。
class _NowCard extends StatelessWidget {
  const _NowCard({required this.now, required this.today});

  final WeatherNow? now;
  final WeatherDay? today;

  @override
  Widget build(BuildContext context) {
    final WeatherNow? n = now;
    if (n == null) return const SizedBox.shrink();
    final WeatherDay? t = today;

    final ThemeData theme = Theme.of(context);
    final String condition = n.text.isNotEmpty
        ? n.text
        : WeatherDataConvert.emoji(n.skycon);
    final String temperature = '${n.temperature?.round() ?? '--'}°';

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(n.city, style: theme.textTheme.headlineMedium),
                ),
                if (t != null)
                  Text(
                    '实时',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
              ],
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                WeatherDataConvert.weatherIcon(context, n.skycon, size: 96),
                const SizedBox(width: 24),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        temperature,
                        style: theme.textTheme.displayLarge?.copyWith(
                          fontSize: 96,
                          fontWeight: FontWeight.w200,
                          height: 1.0,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(condition, style: theme.textTheme.headlineSmall),
                    ],
                  ),
                ),
              ],
            ),
            if (t != null)
              Text(
                '${t.tempMin?.round() ?? '--'}° ~ '
                '${t.tempMax?.round() ?? '--'}°',
                style: theme.textTheme.headlineSmall,
              ),
            Wrap(
              spacing: 28,
              runSpacing: 8,
              children: <Widget>[
                if (n.humidity != null)
                  _InfoItem(
                    icon: Icons.water_drop_outlined,
                    label: '湿度',
                    value: '${n.humidity!.round()}%',
                  ),
                if (n.windSpeed != null)
                  _InfoItem(
                    icon: Icons.air_rounded,
                    label: '风速',
                    value: '${n.windSpeed!.toStringAsFixed(1)} m/s',
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 当前天气的湿度 / 风速信息。
class _InfoItem extends StatelessWidget {
  const _InfoItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 20, color: theme.colorScheme.outline),
        const SizedBox(width: 6),
        Text(
          '$label $value',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// 未来几天的预报区域。
class _ForecastPanel extends StatelessWidget {
  const _ForecastPanel({required this.days, required this.fillHeight});

  final List<WeatherDay> days;

  /// 大屏两栏布局时，每行预报均分剩余高度；窄屏时按内容高度排列。
  final bool fillHeight;

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) return const SizedBox.shrink();
    final ThemeData theme = Theme.of(context);
    final String today = _todayKey();
    final List<Widget> cards = <Widget>[
      for (int i = 0; i < days.length; i++) ...<Widget>[
        if (i > 0) const SizedBox(height: 12),
        if (fillHeight)
          Expanded(
            child: _DayCard(day: days[i], today: today),
          )
        else
          _DayCard(day: days[i], today: today),
      ],
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text('未来 ${days.length} 天', style: theme.textTheme.titleLarge),
        const SizedBox(height: 12),
        if (fillHeight) Expanded(child: Column(children: cards)) else ...cards,
      ],
    );
  }

  /// 今天的 `yyyy-MM-dd`，用于把预报日期转成「今天 / 周X」。
  static String _todayKey() {
    final DateTime now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }
}

/// 单日预报：日期 / 图标 / 天气 / 温度区间。
class _DayCard extends StatelessWidget {
  const _DayCard({required this.day, required this.today});

  final WeatherDay day;
  final String today;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String label = WeatherDataConvert.dayLabel(day.date, today);
    final String displayLabel = label.isEmpty ? day.date : label;
    final String temperature =
        '${day.tempMin?.round() ?? '--'}° ~ '
        '${day.tempMax?.round() ?? '--'}°';

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 72,
              child: Text(
                displayLabel,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            WeatherDataConvert.weatherIcon(context, day.skycon, size: 40),
            const SizedBox(width: 14),
            Expanded(child: Text(day.text, style: theme.textTheme.titleMedium)),
            Text(temperature, style: theme.textTheme.titleLarge),
          ],
        ),
      ),
    );
  }
}
