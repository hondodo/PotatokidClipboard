import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pscreen_screen/features/weather/application/bloc/weather_bloc.dart';
import 'package:pscreen_screen/features/weather/application/bloc/weather_event.dart';
import 'package:pscreen_screen/features/weather/application/bloc/weather_state.dart';
import 'package:pscreen_screen/features/weather/domain/models/weather_models.dart';

/// 天气页：实时天气 + 多日预报（触屏版，UI 自写，数据来自共享包）。
class WeatherPage extends StatelessWidget {
  const WeatherPage({super.key});

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
          return ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              _NowCard(now: data.now),
              const SizedBox(height: 16),
              for (final WeatherDay day in data.daily) ...<Widget>[
                _DayTile(day: day),
                const SizedBox(height: 8),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// 实时天气卡片。
class _NowCard extends StatelessWidget {
  const _NowCard({required this.now});

  final WeatherNow? now;

  @override
  Widget build(BuildContext context) {
    final WeatherNow? n = now;
    if (n == null) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              n.city,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '${n.temperature?.round() ?? '--'}°',
              style: Theme.of(context)
                  .textTheme
                  .displayMedium
                  ?.copyWith(fontWeight: FontWeight.w300),
            ),
            Text(n.text, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                if (n.humidity != null)
                  Text('湿度 ${n.humidity!.round()}%'),
                if (n.humidity != null && n.windSpeed != null)
                  const SizedBox(width: 16),
                if (n.windSpeed != null)
                  Text('风速 ${n.windSpeed!.toStringAsFixed(1)} m/s'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 单日预报行。
class _DayTile extends StatelessWidget {
  const _DayTile({required this.day});

  final WeatherDay day;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(day.date),
        subtitle: Text(day.text),
        trailing: Text(
          '${day.tempMin?.round() ?? '--'}° ~ ${day.tempMax?.round() ?? '--'}°',
        ),
      ),
    );
  }
}
