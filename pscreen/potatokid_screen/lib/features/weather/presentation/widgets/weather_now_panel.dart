import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:potatokid_screen/features/weather/application/bloc/weather_bloc.dart';
import 'package:potatokid_screen/features/weather/application/bloc/weather_state.dart';
import 'package:potatokid_screen/features/weather/data/weather_data_convert.dart';
import 'package:potatokid_screen/features/weather/domain/models/weather_models.dart';

/// 天气小组件：消费全局 [WeatherBloc]，在无数据时不占位、不挡内容。
///
/// 展示：城市 + 当前温度/天气 + 未来 3 天预报。
class WeatherNowPanel extends StatelessWidget {
  const WeatherNowPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WeatherBloc, WeatherState>(
      buildWhen: (WeatherState previous, WeatherState current) =>
          previous.data != current.data || previous.isLoading != current.isLoading,
      builder: (BuildContext context, WeatherState state) {
        final WeatherData? data = state.data;
        if (data == null || data.isEmpty) return const SizedBox.shrink();
        final WeatherNow? now = data.now;
        return Container(
          padding: const EdgeInsets.all(0),
          decoration: BoxDecoration(color: Colors.transparent),
          child: Column(
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (now case final WeatherNow n when n.temperature != null) ...<Widget>[
                    WeatherDataConvert.weatherIcon(context, n.skycon, size: 30),
                    const SizedBox(width: 8),
                    Text(
                      '${n.temperature!.round()}°',
                      style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          n.text.isNotEmpty ? n.text : WeatherDataConvert.emoji(n.skycon),
                          style: const TextStyle(color: Colors.white, fontSize: 15),
                        ),
                        if (n.city.isNotEmpty) Text(n.city, style: const TextStyle(color: Colors.white, fontSize: 12)),
                      ],
                    ),
                  ],
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
