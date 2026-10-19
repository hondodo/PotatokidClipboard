import 'package:app_translator_web/framework/base/base_stateless_underline_bar_widget.dart';
import 'package:app_translator_web/pages/weather/vm/weather_controller.dart';
import 'package:flutter/material.dart';

class WeatherPage extends BaseStatelessUnderlineBarWidget<WeatherController> {
  WeatherPage({
    super.key,
  }) : super(bgColor: Colors.red.withOpacity(0.1));

  @override
  Widget buildBody(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Text(controller.ipInfo.value?.ip ?? ''),
        ),
        SliverToBoxAdapter(
          child: Text(controller.ipInfo.value?.city ?? ''),
        ),
        SliverToBoxAdapter(
          child: Text(controller.ipInfo.value?.region ?? ''),
        ),
        SliverToBoxAdapter(
          child: Text(controller.ipInfo.value?.country ?? ''),
        ),
        SliverToBoxAdapter(
          child: Text(controller.ipInfo.value?.countryName ?? ''),
        ),
        SliverToBoxAdapter(
          child: Text(controller.ipInfo.value?.countryCode ?? ''),
        ),
        SliverToBoxAdapter(
          child: Text(controller.ipInfo.value?.countryCodeIso3 ?? ''),
        ),
      ],
    );
  }

  @override
  String getTitle() {
    return '天气';
  }
}
