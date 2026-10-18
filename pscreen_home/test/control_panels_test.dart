import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/features/home/domain/models/fan_summary.dart';
import 'package:pscreen_home/features/home/domain/models/fridge_summary.dart';
import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';
import 'package:pscreen_home/features/home/domain/models/kettle_summary.dart';
import 'package:pscreen_home/features/home/domain/models/projector_summary.dart';
import 'package:pscreen_home/features/home/domain/models/washer_summary.dart';
import 'package:pscreen_home/features/home/domain/models/water_heater_summary.dart';
import 'package:pscreen_home/features/home/presentation/components/climate_control_panel.dart';
import 'package:pscreen_home/features/home/presentation/components/climate_widget.dart';
import 'package:pscreen_home/features/home/presentation/components/fridge_control_panel.dart';
import 'package:pscreen_home/features/home/presentation/components/fridge_widget.dart';
import 'package:pscreen_home/features/home/presentation/components/fan_control_panel.dart';
import 'package:pscreen_home/features/home/presentation/components/fan_light_widget.dart';
import 'package:pscreen_home/features/home/presentation/components/fan_widget.dart';
import 'package:pscreen_home/features/home/presentation/components/light_control_panel.dart';
import 'package:pscreen_home/features/home/presentation/components/light_widget.dart';
import 'package:pscreen_home/features/home/presentation/components/projector_control_panel.dart';
import 'package:pscreen_home/features/home/presentation/components/projector_remote_sheet.dart';
import 'package:pscreen_home/features/home/presentation/components/projector_widget.dart';
import 'package:pscreen_home/features/home/presentation/components/kettle_control_panel.dart';
import 'package:pscreen_home/features/home/presentation/components/kettle_widget.dart';
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

KettleSummary _kettle() => const KettleSummary(
      deviceId: 'dev_k',
      name: '米家智能电热水瓶 5L',
      status: '待机中',
      temperature: 51,
      fault: '无故障',
      modes: <String>['自来水', '纯净水', '凉白开'],
      mode: '自来水',
      targetTemperature: 100,
      keepWarmTemperature: 55,
      keepWarmOn: true,
      dechlorinationOn: false,
      rapidCoolingOn: false,
      childLocked: true,
      modeEntityId: 'select.k_mode',
      targetEntityId: 'number.k_target',
      keepWarmEntityId: 'switch.k_keep',
      keepWarmTempEntityId: 'number.k_keep',
      dechlorinationEntityId: 'switch.k_dechlor',
      rapidCoolingEntityId: 'switch.k_cool',
      startEntityId: 'notify.k_start',
      stopEntityId: 'button.k_stop',
      lockMode: '50℃及以上热水需要解锁',
    );

FanSummary _fan() => const FanSummary(
      deviceId: 'dev_fan',
      name: '风扇',
      entity: HaEntityStateModel(
        entityId: 'fan.dmaker_cn_811545409_p8_s_2_fan',
        state: 'on',
        attributes: <String, dynamic>{
          'friendly_name': '风扇  风扇',
          'preset_modes': <String>['直吹风', '睡眠风'],
          'preset_mode': '直吹风',
          'percentage': 100,
          'oscillating': false,
        },
      ),
      modes: <String>['直吹风', '睡眠风'],
      mode: '直吹风',
      percentage: 100,
      oscillating: false,
      delayMinutes: 259,
      delayEntityId: 'number.dmaker_cn_811545409_p8_off_delay_time_p_2_10',
    );

FanSummary _fanLight() => const FanSummary(
      deviceId: 'dev_cfan',
      name: '风扇灯',
      entity: HaEntityStateModel(
        entityId: 'fan.xiaomi_cn_991270332_cfan01_s_4_fan',
        state: 'on',
        attributes: <String, dynamic>{
          'friendly_name': '风扇灯  风扇',
          'preset_modes': <String>['直吹风', '自然风', '循环风', '睡眠'],
          'preset_mode': '直吹风',
          'percentage': 100,
          'percentage_step': 1.0,
        },
      ),
      modes: <String>['直吹风', '自然风', '循环风', '睡眠'],
      mode: '直吹风',
      percentage: 100,
      oscillating: false,
      percentageStep: 1,
      delayMinutes: 60,
      delayEntityId: 'number.xiaomi_cn_991270332_cfan01_delay_time_p_6_2',
      delayMaxMinutes: 720,
      supportsOscillation: false,
      masterSwitch: HaEntityStateModel(
        entityId: 'switch.xiaomi_cn_991270332_cfan01_all_on_p_10_1',
        state: 'on',
        attributes: <String, dynamic>{
          'friendly_name': '风扇灯 * 补充 总开关 状态',
        },
      ),
    );

ProjectorSummary _projector() => const ProjectorSummary(
      deviceId: 'dev_proj',
      name: '坚果智能投影仪-N系列',
      isOn: true,
      volume: 31,
      brightness: 10,
      mute: false,
      inputs: <String>['HDMI 1', '媒体中心'],
      apps: <ProjectorApp>[
        ProjectorApp(name: '薯仔看电视', package: 'screen.potatokid.tools'),
        ProjectorApp(name: '云视听小电视', package: 'com.xiaodianshi.tv.yst'),
      ],
      input: '媒体中心',
      currentAppPackage: 'screen.potatokid.tools',
      currentAppName: '薯仔看电视',
      volumeEntityId: 'number.jmgo_volume_p_4_1',
      brightnessEntityId: 'number.jmgo_brightness_p_2_3',
      inputEntityId: 'select.jmgo_input_control_p_2_2',
      muteEntityId: 'switch.jmgo_mute_p_4_2',
      openAppEntityId: 'notify.jmgo_openapp_a_8_1',
      powerOnEntityId: 'button.jmgo_turn_on_a_7_1',
      powerOffEntityId: 'button.jmgo_turn_off_a_2_1',
      powerOnAvailable: true,
      powerOffAvailable: true,
      playEntityId: 'button.jmgo_play_a_3_3',
      pauseEntityId: 'button.jmgo_pause_a_3_4',
      nextEntityId: 'button.jmgo_next_a_3_5',
      previousEntityId: 'button.jmgo_previous_a_3_6',
      stopEntityId: 'button.jmgo_stop_a_3_7',
    );

FridgeSummary _fridge() => const FridgeSummary(
      deviceId: 'dev_fridge',
      name: '米家冰箱 法式平嵌400L',
      mode: '智能',
      modes: <String>['手动', '智能', '速冷', '速冻'],
      modeEntityId: 'select.midjd_mode_p_2_2',
      zones: <FridgeZone>[
        FridgeZone(
          name: '冷藏室',
          currentTemperature: 7,
          targetTemperature: 5,
          minTemperature: 2,
          maxTemperature: 8,
          targetEntityId: 'number.midjd_target_temperature_p_3_2',
        ),
        FridgeZone(
          name: '冷冻室',
          currentTemperature: -20,
          targetTemperature: -18,
          minTemperature: -24,
          maxTemperature: -16,
          targetEntityId: 'number.midjd_target_temperature_p_4_2',
        ),
        FridgeZone(
          name: '变温舱',
          currentTemperature: 2,
          targetTemperature: 5,
          minTemperature: -1,
          maxTemperature: 5,
          targetEntityId: 'number.midjd_target_temperature_p_6_2',
        ),
      ],
      environmentTemperature: 29,
      environmentHumidity: 70,
      refrigeratorOpenTimes: 75,
      freezerOpenTimes: 3,
      totalRuntimeMinutes: 1105,
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
              areaLabel: '阳台',
              isToggling: false,
              onToggle: () {},
              onOpenDetail: () {},
            ),
          ),
        ),
      ),
    ));

    expect(find.text('米家洗衣机 洗烘12kg'), findsOneWidget);
    expect(find.text('阳台 · 已关机'), findsOneWidget);
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

  testWidgets('热水瓶卡片：温度 / 状态 / 开始动作在 240x112 内无溢出',
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
            child: KettleWidget(
              summary: _kettle(),
              onStart: () {},
              onStop: () {},
              onOpenDetail: () {},
            ),
          ),
        ),
      ),
    ));

    expect(find.textContaining('51', findRichText: true), findsOneWidget);
    expect(find.text('目标 100°C'), findsOneWidget);
    expect(find.text('加热'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('热水瓶面板：模式 / 温度 / 开关无溢出',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_host(KettleControlPanel(
      summary: _kettle(),
      isBusy: false,
      onStart: () {},
      onStop: () {},
      onModeSelected: (_) {},
      onTargetTemperatureChanged: (_) {},
      onKeepWarmTemperatureChanged: (_) {},
      onToggleKeepWarm: () {},
      onToggleDechlorination: () {},
      onToggleRapidCooling: () {},
    )));

    expect(find.text('自来水'), findsOneWidget);
    expect(find.text('加热温度'), findsOneWidget);
    expect(find.text('保温温度'), findsOneWidget);
    expect(find.text('除氯'), findsOneWidget);
    expect(find.text('风冷'), findsOneWidget);
    expect(find.text('开始加热'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('风扇卡片：模式 / 档位 / 摆风在 240x112 内无溢出',
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
            child: FanWidget(
              summary: _fan(),
              isToggling: false,
              onToggle: () {},
              onOpenDetail: () {},
            ),
          ),
        ),
      ),
    ));

    expect(find.text('直吹风'), findsOneWidget);
    expect(find.text('三挡 · 摆风关'), findsOneWidget);
    expect(find.byTooltip('关闭风扇'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('风扇面板：模式 / 三挡 / 摆风 / 延时无溢出',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_host(FanControlPanel(
      summary: _fan(),
      isToggling: false,
      onToggle: () {},
      onModeSelected: (_) {},
      onSpeedSelected: (_) {},
      onPercentageChanged: (_) {},
      onOscillatingChanged: (_) {},
      onDelayChanged: (_) {},
    )));

    expect(find.text('模式'), findsOneWidget);
    expect(find.text('睡眠风'), findsOneWidget);
    expect(find.text('风机档位 | 三挡'), findsOneWidget);
    expect(find.text('左右摆风'), findsOneWidget);
    expect(find.text('延时关闭'), findsOneWidget);
    expect(find.text('4小时19分钟'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('风扇灯面板：无级调速 / 无摆风 / 12 小时延时',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_host(FanControlPanel(
      summary: _fanLight(),
      isToggling: false,
      onToggle: () {},
      onModeSelected: (_) {},
      onSpeedSelected: (_) {},
      onPercentageChanged: (_) {},
      onOscillatingChanged: (_) {},
      onDelayChanged: (_) {},
    )));

    expect(find.text('无级调速'), findsOneWidget);
    expect(find.text('自然风'), findsOneWidget);
    expect(find.text('左右摆风'), findsNothing);
    expect(find.text('12小时'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('风扇灯组合卡：灯亮度 + 风扇状态在 240x112 内无溢出',
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
            child: FanLightWidget(
              light: _light(),
              fan: _fanLight(),
              isToggling: false,
              onToggleMaster: () {},
              onOpenDetail: () {},
            ),
          ),
        ),
      ),
    ));

    expect(find.text('灯 80%'), findsOneWidget);
    expect(find.text('直吹风 100'), findsOneWidget);
    expect(find.byTooltip('关闭总开关'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('风扇灯总开关行：双图标 + 总开关', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_host(FanLightMasterRow(
      name: '风扇灯',
      master: _fanLight().masterSwitch!,
      isToggling: false,
      onToggle: () {},
    )));

    expect(find.text('总开关'), findsOneWidget);
    expect(find.text('风扇灯 · 已开启'), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('投影仪卡片：应用 / 音量 / 亮度在 240x112 内无溢出',
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
            child: ProjectorWidget(
              summary: _projector(),
              areaLabel: '客厅',
              isBusy: false,
              onPower: () {},
              onOpenDetail: () {},
            ),
          ),
        ),
      ),
    ));

    expect(find.text('薯仔看电视'), findsOneWidget);
    expect(find.text('音量 31% · 亮度 10'), findsOneWidget);
    expect(find.byTooltip('关机'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('投影仪面板：应用 / 输入源 / 音量 / 亮度 / 播放控制',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_host(ProjectorControlPanel(
      summary: _projector(),
      isBusy: false,
      onPower: () {},
      onVolumeChanged: (_) {},
      onBrightnessChanged: (_) {},
      onInputSelected: (_) {},
      onMuteToggle: () {},
      onOpenApp: (_) {},
      onButtonPressed: (_) {},
    )));

    expect(find.text('应用'), findsOneWidget);
    expect(find.text('输入源'), findsOneWidget);
    expect(find.text('音量'), findsOneWidget);
    expect(find.text('亮度'), findsOneWidget);
    expect(find.text('静音'), findsOneWidget);
    expect(find.text('媒体中心'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('投影仪虚拟遥控：方向键 / OK / 音量发送对应 code',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final List<int> keys = <int>[];
    bool powered = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ProjectorRemoteSheet(
          isOn: true,
          onPower: () => powered = true,
          onKey: keys.add,
        ),
      ),
    ));

    await tester.tap(find.byTooltip('OK键'));
    await tester.tap(find.byTooltip('上键'));
    await tester.tap(find.byTooltip('左键'));
    await tester.tap(find.byTooltip('返回键'));
    await tester.tap(find.byTooltip('对焦加'));
    await tester.tap(find.byTooltip('音量减键'));
    await tester.tap(find.byTooltip('关机'));

    expect(keys, <int>[7, 5, 3, 2, 12, 8]);
    expect(powered, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('投影仪遥控横屏：左右分栏无溢出', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ProjectorRemoteSheet(
          isOn: true,
          onPower: () {},
          onKey: (_) {},
        ),
      ),
    ));

    expect(find.byTooltip('OK键'), findsOneWidget);
    expect(find.byTooltip('上键'), findsOneWidget);
    expect(find.byTooltip('音量加键'), findsOneWidget);
    expect(find.text('遥控器'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('冰箱卡片：三舱温度在 240x112 内无溢出',
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
            child: FridgeWidget(
              summary: _fridge(),
              areaLabel: '厨房',
              onOpenDetail: () {},
            ),
          ),
        ),
      ),
    ));

    expect(find.text('冷藏室'), findsOneWidget);
    expect(find.text('冷冻室'), findsOneWidget);
    expect(find.text('变温舱'), findsOneWidget);
    expect(find.text('厨房 · 智能模式'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('冰箱面板：三舱目标温度 / 模式 / 环境信息',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    String? changedEntity;
    int? changedValue;
    await tester.pumpWidget(_host(FridgeControlPanel(
      summary: _fridge(),
      onModeSelected: (_) {},
      onTargetChanged: (String id, int value) {
        changedEntity = id;
        changedValue = value;
      },
    )));

    expect(find.text('冰箱模式'), findsOneWidget);
    expect(find.text('速冷'), findsOneWidget);
    expect(find.text('冷藏室'), findsWidgets);
    expect(find.text('食材管理是米家云端数据，HA 未暴露食材列表；这里只控制温度与模式。'),
        findsOneWidget);

    await tester.tap(find.byTooltip('冷藏室温度 +'));
    expect(changedEntity, 'number.midjd_target_temperature_p_3_2');
    expect(changedValue, 6);
    expect(tester.takeException(), isNull);
  });
}
