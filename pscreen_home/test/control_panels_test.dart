import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';
import 'package:pscreen_home/features/home/domain/models/washer_summary.dart';
import 'package:pscreen_home/features/home/domain/models/water_heater_summary.dart';
import 'package:pscreen_home/features/home/presentation/components/climate_control_panel.dart';
import 'package:pscreen_home/features/home/presentation/components/climate_widget.dart';
import 'package:pscreen_home/features/home/presentation/components/light_control_panel.dart';
import 'package:pscreen_home/features/home/presentation/components/light_widget.dart';
import 'package:pscreen_home/features/home/presentation/components/value_widget.dart';
import 'package:pscreen_home/features/home/presentation/components/washer_control_panel.dart';
import 'package:pscreen_home/features/home/presentation/components/washer_widget.dart';
import 'package:pscreen_home/features/home/presentation/components/water_heater_control_panel.dart';
import 'package:pscreen_home/features/home/presentation/components/water_heater_widget.dart';

HaEntityStateModel _light() => const HaEntityStateModel(
      entityId: 'light.bedroom',
      state: 'on',
      attributes: <String, dynamic>{
        'friendly_name': '卧室大灯',
        'brightness': 204,
        'color_temp_kelvin': 3500,
        'min_color_temp_kelvin': 2700,
        'max_color_temp_kelvin': 5700,
        'supported_color_modes': <String>['color_temp'],
        'effect_list': <String>['明亮模式', '电视模式'],
        'effect': '电视模式',
      },
    );

HaEntityStateModel _climate() => const HaEntityStateModel(
      entityId: 'climate.bedroom',
      state: 'cool',
      attributes: <String, dynamic>{
        'friendly_name': '卧室空调',
        'temperature': 26.5,
        'min_temp': 16,
        'max_temp': 31,
        'target_temp_step': 0.5,
        'current_temperature': 35.0,
        'current_humidity': 55,
        'hvac_modes': <String>['cool', 'heat', 'dry', 'fan_only', 'off'],
        'fan_modes': <String>['自动', '一档', '二档', '三档', 'Max档'],
        'fan_mode': '三档',
        'swing_modes': <String>['off', 'vertical'],
        'swing_mode': 'off',
      },
    );

WasherSummary _washer({bool on = false, bool running = false}) =>
    WasherSummary(
      deviceId: 'dev_wm',
      name: '米家洗衣机 洗烘12kg',
      status: running ? '工作中' : (on ? '待机中' : '已关机'),
      runStatus: running ? '主洗中' : '未运行',
      isOn: on,
      modes: const <String>['智能洗', '快速洗', '单烘干', '筒清洁'],
      remainingMinutes: running ? 32 : null,
      doorState: '舱门已开',
      fault: 'No Faults',
      mode: '智能洗',
      powerEntityId: 'switch.wm_on',
      modeEntityId: 'select.wm_mode',
      startEntityId: 'button.wm_start',
      pauseEntityId: 'button.wm_pause',
      stopEntityId: 'button.wm_stop',
      energyKwh: 14,
      waterConsumption: 521,
      washedTimes: 85,
    );

WaterHeaterSummary _waterHeater() => WaterHeaterSummary(
      deviceId: 'dev_wh',
      name: '米家智能零冷水燃气热水器16L N1',
      entity: const HaEntityStateModel(
        entityId: 'water_heater.wh',
        state: '自定义',
        attributes: <String, dynamic>{
          'friendly_name': '米家智能零冷水燃气热水器16L N1  热水器',
          'min_temp': 35,
          'max_temp': 65,
          'target_temp_step': 1,
          'temperature': 40,
          'current_temperature': 33,
          'operation_list': <String>[
            '自定义',
            'AI控温',
            '婴童洗',
            '舒适洗',
            '宠物洗',
            '厨房用',
            'off',
          ],
        },
      ),
      status: '待机中',
      fault: '0',
      inletTemperature: 31,
      flowRate: 0,
      preheatEntityId: 'switch.wh_preheat',
      preheatOn: false,
      timerPreheatEntityId: 'switch.wh_timer',
      timerPreheatOn: true,
    );

Widget _host(Widget child) => MaterialApp(
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: child,
        ),
      ),
    );

void main() {
  testWidgets('灯光面板：百分比、色温、效果都渲染且无溢出', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_host(LightControlPanel(
      entity: _light(),
      isToggling: false,
      areaLabel: '金科1204 卧室',
      onToggle: () {},
      onBrightnessChanged: (_) {},
      onColorTemperatureChanged: (_) {},
      onEffectSelected: (_) {},
    )));

    expect(find.text('卧室大灯'), findsOneWidget);
    expect(find.text('80%'), findsOneWidget);
    expect(find.text('电视模式'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('空调面板：目标温度、模式、风速、摆风都渲染且无溢出',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_host(ClimateControlPanel(
      entity: _climate(),
      isToggling: false,
      areaLabel: '金科1204 卧室',
      onToggle: () {},
      onTemperatureChanged: (_) {},
      onHvacModeSelected: (_) {},
      onFanModeSelected: (_) {},
      onSwingModeSelected: (_) {},
    )));

    expect(find.textContaining('26.5', findRichText: true), findsOneWidget);
    expect(find.text('35°C'), findsOneWidget);
    expect(find.text('55%'), findsOneWidget);
    expect(find.text('三档'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('空调卡电源键：直接开关，不进入详情', (WidgetTester tester) async {
    bool toggled = false;
    bool opened = false;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 240,
            height: 112,
            child: ClimateWidget(
              entity: _climate().copyWith(state: 'off'),
              isToggling: false,
              areaLabel: '卧室',
              onToggle: () => toggled = true,
              onIncrease: () {},
              onDecrease: () {},
              onOpenDetail: () => opened = true,
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.byTooltip('开启空调'));
    await tester.pump();

    expect(toggled, isTrue);
    expect(opened, isFalse, reason: '电源键不应冒泡成卡片点击');
  });

  testWidgets('首页灯卡 / 空调卡在 240x112 网格内无溢出',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(600, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: Wrap(
            spacing: 12,
            children: <Widget>[
              SizedBox(
                width: 240,
                height: 112,
                child: LightWidget(
                  entity: _light(),
                  isToggling: false,
                  areaLabel: '卧室',
                  onToggle: () {},
                  onBrightnessChanged: (_) {},
                ),
              ),
              SizedBox(
                width: 240,
                height: 112,
                child: ClimateWidget(
                  entity: _climate(),
                  isToggling: false,
                  areaLabel: '卧室',
                  onToggle: () {},
                  onIncrease: () {},
                  onDecrease: () {},
                ),
              ),
            ],
          ),
        ),
      ),
    ));

    expect(find.text('80%'), findsOneWidget);
    expect(find.textContaining('26.5', findRichText: true), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('洗衣机卡片：状态 / 统计 / 电源键在 240x112 内无溢出',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 240,
            height: 112,
            child: WasherWidget(
              summary: _washer(),
              isToggling: false,
              onToggle: () {},
              onOpenDetail: () {},
            ),
          ),
        ),
      ),
    ));

    expect(find.text('米家洗衣机 洗烘12kg'), findsOneWidget);
    expect(find.text('已关机'), findsOneWidget);
    expect(find.byTooltip('开启洗衣机'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('洗衣机面板：运行中显示剩余时间，启动禁用、暂停可用',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_host(WasherControlPanel(
      summary: _washer(on: true, running: true),
      isToggling: false,
      onToggle: () {},
      onModeSelected: (_) {},
      onStart: () {},
      onPause: () {},
      onStop: () {},
    )));

    expect(find.text('主洗中 · 剩余 32 分钟'), findsOneWidget);
    expect(find.textContaining('14', findRichText: true), findsOneWidget);
    expect(find.textContaining('521', findRichText: true), findsOneWidget);
    expect(find.textContaining('85', findRichText: true), findsOneWidget);
    expect(find.text('智能洗'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, '启动')).onPressed,
      isNull,
      reason: '运行中不能重复启动',
    );
    expect(
      tester
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '暂停'))
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('ValueWidget：传感器显示值与单位', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 240,
            height: 112,
            child: ValueWidget(
              entity: const HaEntityStateModel(
                entityId: 'sensor.temperature',
                state: '24.5',
                attributes: <String, dynamic>{
                  'friendly_name': '阳台温度',
                  'unit_of_measurement': '°C',
                },
              ),
              areaLabel: '阳台',
            ),
          ),
        ),
      ),
    ));

    expect(find.text('阳台温度'), findsOneWidget);
    expect(find.textContaining('24.5 °C', findRichText: true), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('热水器卡片：目标温度 / 状态在 240x112 内无溢出',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final WaterHeaterSummary summary = _waterHeater();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 240,
            height: 112,
            child: WaterHeaterWidget(
              entity: summary.entity,
              statusLabel: summary.statusLabel,
              isToggling: false,
              onToggle: () {},
              onIncrease: () {},
              onDecrease: () {},
              onOpenDetail: () {},
            ),
          ),
        ),
      ),
    ));

    expect(find.textContaining('40', findRichText: true), findsOneWidget);
    expect(find.textContaining('待机中'), findsOneWidget);
    expect(find.byTooltip('关闭热水器'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('热水器面板：模式 / 温度 / 预热开关无溢出',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_host(WaterHeaterControlPanel(
      summary: _waterHeater(),
      isToggling: false,
      onToggle: () {},
      onTemperatureChanged: (_) {},
      onModeSelected: (_) {},
      onPreheatToggle: () {},
      onTimerPreheatToggle: () {},
    )));

    expect(find.textContaining('40', findRichText: true), findsWidgets);
    expect(find.text('AI控温'), findsOneWidget);
    expect(find.text('预热'), findsOneWidget);
    expect(find.text('定时预热'), findsOneWidget);
    expect(find.textContaining('33', findRichText: true), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
