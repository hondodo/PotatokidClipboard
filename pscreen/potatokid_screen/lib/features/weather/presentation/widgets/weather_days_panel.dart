import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:potatokid_screen/features/weather/application/bloc/weather_bloc.dart';
import 'package:potatokid_screen/features/weather/application/bloc/weather_state.dart';
import 'package:potatokid_screen/features/weather/data/weather_data_convert.dart';
import 'package:potatokid_screen/features/weather/domain/models/weather_models.dart';

/// 天气小组件：消费全局 [WeatherBloc]，在无数据时不占位、不挡内容。
///
/// 未来 n 天预报
class WeatherDaysPanel extends StatelessWidget {
  const WeatherDaysPanel({super.key, this.dayCount = 3});
  final int dayCount;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WeatherBloc, WeatherState>(
      buildWhen: (WeatherState previous, WeatherState current) =>
          previous.data != current.data || previous.isLoading != current.isLoading,
      builder: (BuildContext context, WeatherState state) {
        final WeatherData? data = state.data;
        if (data == null || data.isEmpty) return const SizedBox.shrink();
        final List<WeatherDay> days = data.daily.take(dayCount).toList();
        return Row(mainAxisSize: MainAxisSize.min, children: <Widget>[..._buildDays(context, days)]);
      },
    );
  }

  /// 未来几天（今天起 3 天）：白天天气 + 最高/最低。
  List<Widget> _buildDays(BuildContext context, List<WeatherDay> days) {
    final String today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    return <Widget>[
      for (final WeatherDay d in days)
        Padding(
          padding: EdgeInsetsGeometry.only(left: d == days.first ? 0 : 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                WeatherDataConvert.dayLabel(d.date, today),
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Text(
                    '${d.tempMin?.round() ?? '-'}°/${d.tempMax?.round() ?? '-'}°',
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              WeatherDataConvert.weatherIcon(context, d.skycon, size: 22),
            ],
          ),
        ),
    ];
  }
}
