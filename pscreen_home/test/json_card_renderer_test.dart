import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pscreen_home/app/config/ha_config.dart';
import 'package:pscreen_home/features/home/domain/models/card_layout.dart';
import 'package:pscreen_home/features/home/domain/models/device_type_dictionary.dart';
import 'package:pscreen_home/features/home/domain/models/ha_device_group.dart';
import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';
import 'package:pscreen_home/features/home/domain/models/metric.dart';
import 'package:pscreen_home/features/home/application/metric_history.dart';
import 'package:pscreen_home/features/home/presentation/components/cached_card_icon.dart';
import 'package:pscreen_home/features/home/presentation/components/gradient_slider.dart';
import 'package:pscreen_home/features/home/presentation/components/json_card_renderer.dart';

HaEntityStateModel _entity(String id, String state, {String name = ''}) =>
    HaEntityStateModel(
      entityId: id,
      state: state,
      attributes: <String, dynamic>{'friendly_name': name.isEmpty ? id : name},
    );

void main() {
  testWidgets('JsonCardRenderer 渲染通用默认布局不抛异常', (WidgetTester tester) async {
    final HaDeviceGroup group = HaDeviceGroup(
      deviceId: 'dev_socket',
      title: '客厅插座',
      entities: <HaEntityStateModel>[
        _entity('switch.socket_on', 'on', name: '插座'),
        _entity('sensor.power', '65', name: '功率'),
      ],
    );
    const DeviceCardConfig card = DeviceCardConfig(
      label: '开关状态',
      mainFmt: '{v}',
      subTpl: '{state}',
      icon: '⏻',
      color: '#4dd4ac',
      buttons: <DeviceCardButton>[
        DeviceCardButton(label: '开关', action: 'toggle'),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 188,
            child: JsonCardRenderer(
              group: group,
              card: card,
              typeKey: 'socket',
              onOpenDetail: () {},
              onAction: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // 渲染成功 = 没抛异常；验证标题出现。
    expect(find.textContaining('客厅插座'), findsWidgets);
  });

  testWidgets('JsonCardRenderer 渲染 multi_switch 每路大按钮不抛异常', (
    WidgetTester tester,
  ) async {
    final HaDeviceGroup group = HaDeviceGroup(
      deviceId: 'dev_sw',
      title: '小米双开',
      entities: <HaEntityStateModel>[
        _entity('switch.a_on_p_2_1', 'on', name: '左键'),
        _entity('switch.a_on_p_3_1', 'off', name: '右键'),
      ],
    );
    const DeviceCardConfig card = DeviceCardConfig(
      label: '已开启路数',
      mainFmt: '{v}',
      subTpl: '{state}',
      icon: '▦',
      color: '#a3a3a3',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 260,
            child: JsonCardRenderer(
              group: group,
              card: card,
              typeKey: 'multi_switch',
              onOpenDetail: () {},
              onAction: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // 每路一个大按钮：label 显示的应该是实体名（左键/右键），不是"已开启路数 2/4"。
    expect(find.textContaining('左键'), findsWidgets);
    expect(find.textContaining('右键'), findsWidgets);
  });

  testWidgets('JsonCardRenderer 渲染服务端自定义 layout(含sparkline)不抛异常', (
    WidgetTester tester,
  ) async {
    final HaDeviceGroup group = HaDeviceGroup(
      deviceId: 'dev_socket',
      title: '客厅插座',
      entities: <HaEntityStateModel>[
        _entity('switch.socket_on', 'on', name: '插座'),
      ],
    );
    final CardLayoutNode layout = CardLayoutNode.fromJson(<String, dynamic>{
      'type': 'column',
      'gap': 8,
      'children': <dynamic>[
        <String, dynamic>{'type': 'text', 'value': '{title}', 'size': 14},
        <String, dynamic>{
          'type': 'text',
          'value': '{main}',
          'size': 24,
          'color': '{color}',
        },
        <String, dynamic>{
          'type': 'sparkline',
          'metric': 'power',
          'height': 60,
          'showLabels': true,
        },
      ],
    });
    final DeviceCardConfig card = DeviceCardConfig(
      label: '功率',
      mainFmt: '{v}W',
      subTpl: '{state}',
      color: '#4dd4ac',
      layout: layout,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 260,
            child: JsonCardRenderer(
              group: group,
              card: card,
              typeKey: 'socket',
              onOpenDetail: () {},
              onAction: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('客厅插座'), findsWidgets);
  });

  testWidgets('JsonCardRenderer 渲染 row 内未标记 expand 的 column 不抛无限宽度异常', (
    WidgetTester tester,
  ) async {
    final HaDeviceGroup group = HaDeviceGroup(
      deviceId: 'dev_light',
      title: '客厅 大灯',
      entities: <HaEntityStateModel>[
        _entity('light.living', 'off', name: '大灯'),
      ],
    );
    // 后台下发的布局：row 里套 column，但 column 没有写 expand。
    // Row 会给非 flex 子节点无界宽度，column 默认 stretch 会把无界宽度
    // 传给 Text，曾导致 "BoxConstraints forces an infinite width"。
    final CardLayoutNode layout = CardLayoutNode.fromJson(<String, dynamic>{
      'type': 'column',
      'gap': 8,
      'children': <dynamic>[
        <String, dynamic>{
          'type': 'row',
          'gap': 10,
          'crossAlign': 'center',
          'children': <dynamic>[
            <String, dynamic>{'type': 'icon', 'value': '✦', 'size': 24},
            <String, dynamic>{
              'type': 'column',
              'gap': 2,
              'children': <dynamic>[
                <String, dynamic>{
                  'type': 'text',
                  'value': '{title}',
                  'size': 14,
                  'weight': 600,
                  'maxLines': 1,
                },
                <String, dynamic>{'type': 'divider', 'thickness': 2, 'gap': 2},
                <String, dynamic>{
                  'type': 'text',
                  'value': '{sub}',
                  'size': 12,
                  'color': '{color}',
                  'maxLines': 1,
                },
              ],
            },
          ],
        },
      ],
    });
    final DeviceCardConfig card = DeviceCardConfig(
      label: '开关状态',
      mainFmt: '{v}',
      subTpl: '{state}',
      icon: '✦',
      color: '#4dd4ac',
      layout: layout,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 188,
            child: JsonCardRenderer(
              group: group,
              card: card,
              typeKey: 'light',
              onOpenDetail: () {},
              onAction: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('客厅 大灯'), findsWidgets);
  });

  test('CardEvalContext.parseValueMap 解析 ESP 风格替换表', () {
    final Map<String, String>? map = CardEvalContext.parseValueMap(
      'on=着灯,off=关闭；open=开，close=关\nanother=\'带引号值\'',
    );
    expect(map, isNotNull);
    expect(map!['on'], '着灯');
    expect(map['off'], '关闭');
    expect(map['open'], '开');
    expect(map['close'], '关');
    expect(map['another'], '带引号值');
    expect(CardEvalContext.parseValueMap(''), isNull);
  });

  test('resolve 应用值替换但不影响条件判断', () {
    final HaDeviceGroup group = HaDeviceGroup(
      deviceId: 'dev_light',
      title: '客厅 大灯',
      entities: <HaEntityStateModel>[
        _entity('light.living', 'off', name: '大灯'),
      ],
    );
    const DeviceCardConfig card = DeviceCardConfig(subTpl: '{state}');
    final CardEvalContext ctx = CardEvalContext(group: group, card: card);
    final Map<String, String> map = <String, String>{'on': '着灯', 'off': '关闭'};

    // 文本求值：off -> 关闭；其他占位符（亮度=0）不被误替换。
    expect(ctx.resolve('{state}', map), '关闭');
    expect(ctx.resolve('{state} · 亮度{brightnessPercent}%', map), '关闭 · 亮度0%');
    // 条件判断不传 map，始终基于原始值。
    expect(ctx.resolve('{state}'), 'off');
    expect(ctx.evalCondition('{state} = off'), isTrue);
    expect(ctx.evalCondition('{state} = 关闭'), isFalse);
  });

  testWidgets('JsonCardRenderer 圆形按钮 + 可交互亮度条渲染并派发亮度动作', (
    WidgetTester tester,
  ) async {
    final HaDeviceGroup group = HaDeviceGroup(
      deviceId: 'dev_light',
      title: '客厅 大灯',
      entities: <HaEntityStateModel>[
        HaEntityStateModel(
          entityId: 'light.living',
          state: 'on',
          attributes: <String, dynamic>{
            'friendly_name': '大灯',
            'brightness': 64, // 25%
            'supported_color_modes': <String>['brightness'],
          },
        ),
      ],
    );
    final CardLayoutNode layout = CardLayoutNode.fromJson(<String, dynamic>{
      'type': 'column',
      'gap': 8,
      'children': <dynamic>[
        <String, dynamic>{
          'type': 'text',
          'value': '{state} · 亮度{brightnessPercent}%',
          'map': 'on=着灯,off=关闭',
        },
        <String, dynamic>{
          'type': 'button',
          'round': true,
          'value': 'power_settings_new',
          'onClick': 'toggle@{primary.entityId}',
        },
        <String, dynamic>{
          'type': 'progress',
          'interactive': true,
          'value': '{brightnessPercent}',
          'onClick': 'brightness', // 自动选组内支持调光的灯
          'height': 12,
        },
      ],
    });
    final DeviceCardConfig card = DeviceCardConfig(
      label: '灯光状态',
      mainFmt: '{v}',
      subTpl: '{state}',
      icon: '✦',
      color: '#ff6a3a',
      layout: layout,
    );
    final List<String> actions = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 220,
            child: JsonCardRenderer(
              group: group,
              card: card,
              typeKey: 'light',
              onOpenDetail: () {},
              onAction: actions.add,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // 值替换生效：on -> 着灯。
    expect(find.textContaining('着灯 · 亮度25%'), findsOneWidget);
    // 圆形电源键点击派发 toggle@。
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(actions, contains('toggle@light.living'));

    // 点亮度条中部：GradientSlider 松手派发 brightness@实体:百分比。
    final GradientSlider slider = tester.widget<GradientSlider>(
      find.byType(GradientSlider),
    );
    slider.onChangeEnd?.call(60);
    expect(
      actions.any((String a) => a.startsWith('brightness@light.living:')),
      isTrue,
    );
  });

  testWidgets('风扇风速条 onClick fan@{id:后缀} 拼出 fan@实体:百分比', (
    WidgetTester tester,
  ) async {
    final HaDeviceGroup group = HaDeviceGroup(
      deviceId: 'dev_fanlight',
      title: '风扇灯',
      entities: <HaEntityStateModel>[
        _entity('fan.xiaomi_cn_991270332_cfan01_s_4_fan', 'on', name: '风扇'),
      ],
    );
    final CardLayoutNode layout = CardLayoutNode.fromJson(<String, dynamic>{
      'type': 'column',
      'children': <dynamic>[
        <String, dynamic>{
          'type': 'progress',
          'interactive': true,
          'value': '{a:_s_4_fan.percentage}',
          'onClick': 'fan@{id:_s_4_fan}',
          'height': 12,
        },
      ],
    });
    final DeviceCardConfig card = DeviceCardConfig(
      label: '风扇状态',
      mainFmt: '{v}',
      subTpl: '{state}',
      icon: '风',
      color: '#4dd0c4',
      layout: layout,
    );
    final List<String> actions = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 120,
            child: JsonCardRenderer(
              group: group,
              card: card,
              typeKey: 'fan_light',
              onOpenDetail: () {},
              onAction: actions.add,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final GradientSlider slider = tester.widget<GradientSlider>(
      find.byType(GradientSlider),
    );
    slider.onChangeEnd?.call(66);
    expect(actions, contains('fan@fan.xiaomi_cn_991270332_cfan01_s_4_fan:66'));
  });

  testWidgets('风速条走 onActionResult 回传下发结果，不重复调用 onAction', (
    WidgetTester tester,
  ) async {
    final HaDeviceGroup group = HaDeviceGroup(
      deviceId: 'dev_fanlight_result',
      title: '风扇灯',
      entities: <HaEntityStateModel>[
        _entity('fan.xxx_s_4_fan', 'on', name: '风扇'),
      ],
    );
    final DeviceCardConfig card = DeviceCardConfig(
      layout: CardLayoutNode.fromJson(<String, dynamic>{
        'type': 'progress',
        'interactive': true,
        'value': '{a:_s_4_fan.percentage}',
        'onClick': 'fan@{id:_s_4_fan}',
      }),
    );
    final List<String> results = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 120,
            child: JsonCardRenderer(
              group: group,
              card: card,
              typeKey: 'fan_light',
              onOpenDetail: () {},
              onAction: (String _) => fail('有 onActionResult 时不应重复下发'),
              onActionResult: (String action) async {
                results.add(action);
                return false;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final GradientSlider slider = tester.widget<GradientSlider>(
      find.byType(GradientSlider),
    );
    expect(await slider.onChangeEndAsync!.call(66), isFalse);
    expect(results, contains('fan@fan.xxx_s_4_fan:66'));
  });

  testWidgets('多路开关双开布局：状态左键开右键关，按钮显示要执行的动作', (
    WidgetTester tester,
  ) async {
    const String leftId =
        'switch.zimi_cn_1065542586_dhkg02_on_p_2_1';
    const String rightId =
        'switch.zimi_cn_1065542586_dhkg02_on_p_3_1';
    final HaDeviceGroup group = HaDeviceGroup(
      deviceId: '49e727feb2ed312cfd8426d73bb79a1a',
      title: '小米米家智能开关（双开单控）',
      entities: <HaEntityStateModel>[
        _entity(leftId, 'on', name: '客厅灯 左键'),
        _entity(rightId, 'off', name: '右键'),
      ],
    );
    final DeviceCardConfig card = DeviceCardConfig(
      color: '#64B5F6',
      layout: CardLayoutNode.fromJson(<String, dynamic>{
        'type': 'column',
        'gap': 8,
        'children': <dynamic>[
          <String, dynamic>{
            'type': 'row',
            'gap': 6,
            'children': <dynamic>[
              <String, dynamic>{
                'type': 'text',
                'value': '左键{s:_p_2_1}',
                'map': 'on=开,off=关',
                'visibleWhen': '{id:_p_2_1}',
              },
              <String, dynamic>{
                'type': 'text',
                'value': '右键{s:_p_3_1}',
                'map': 'on=开,off=关',
                'visibleWhen': '{id:_p_3_1}',
              },
              <String, dynamic>{
                'type': 'text',
                'value': '3路{s:_p_4_1}',
                'map': 'on=开,off=关',
                'visibleWhen': '{id:_p_4_1}',
              },
            ],
          },
          <String, dynamic>{
            'type': 'row',
            'gap': 8,
            'children': <dynamic>[
              <String, dynamic>{
                'type': 'chip',
                'label': '{s:_p_2_1}',
                'map': 'on=关闭,off=开启',
                'onClick': 'toggle@{id:_p_2_1}',
                'expand': true,
              },
              <String, dynamic>{
                'type': 'chip',
                'label': '{s:_p_3_1}',
                'map': 'on=关闭,off=开启',
                'onClick': 'toggle@{id:_p_3_1}',
                'expand': true,
              },
            ],
          },
        ],
      }),
    );
    final List<String> actions = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 150,
            child: JsonCardRenderer(
              group: group,
              card: card,
              typeKey: 'multi_switch',
              onOpenDetail: () {},
              onAction: actions.add,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('左键开'), findsOneWidget);
    expect(find.text('右键关'), findsOneWidget);
    expect(find.textContaining('3路'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, '关闭'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '开启'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, '关闭'));
    await tester.pumpAndSettle();
    expect(actions, contains('toggle@$leftId'));
  });

  testWidgets('离线设备亮度条仍常显（offline=true），不隐藏不禁用显示', (WidgetTester tester) async {
    // 离线实体：state=unavailable → group.isUnavailable=true → progress offline
    final HaDeviceGroup group = HaDeviceGroup(
      deviceId: 'dev_light_offline',
      title: '客厅 大灯',
      entities: <HaEntityStateModel>[
        HaEntityStateModel(
          entityId: 'light.living',
          state: 'unavailable',
          attributes: <String, dynamic>{
            'friendly_name': '大灯',
            'brightness': 64,
            'supported_color_modes': <String>['brightness'],
          },
        ),
      ],
    );
    final CardLayoutNode layout = CardLayoutNode.fromJson(<String, dynamic>{
      'type': 'column',
      'children': <dynamic>[
        <String, dynamic>{
          'type': 'progress',
          'interactive': true,
          'value': '{brightnessPercent}',
          'onClick': 'brightness',
          'height': 12,
        },
      ],
    });
    final DeviceCardConfig card = DeviceCardConfig(
      label: '灯光状态',
      mainFmt: '{v}',
      subTpl: '{state}',
      icon: '☀',
      color: '#facc15',
      layout: layout,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 120,
            child: JsonCardRenderer(
              group: group,
              card: card,
              typeKey: 'light',
              onOpenDetail: () {},
              onAction: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // 无论在线离线，GradientSlider 都必须渲染出来（常显）
    expect(find.byType(GradientSlider), findsOneWidget);
    final GradientSlider slider = tester.widget<GradientSlider>(
      find.byType(GradientSlider),
    );
    expect(slider.offline, isTrue, reason: '离线设备应使用暗灰配色');
  });

  testWidgets('单字符符号图标用 Text 渲染，不再回退成圆圈', (WidgetTester tester) async {
    final HaDeviceGroup group = HaDeviceGroup(
      deviceId: 'dev_light_icon',
      title: '客厅 大灯',
      entities: <HaEntityStateModel>[_entity('light.living', 'on', name: '大灯')],
    );
    final CardLayoutNode layout = CardLayoutNode.fromJson(<String, dynamic>{
      'type': 'column',
      'children': <dynamic>[
        <String, dynamic>{
          'type': 'icon',
          'value': '{icon}',
          'size': 26,
          'box': <String, dynamic>{'size': 48, 'color': '#facc15'},
        },
      ],
    });
    final DeviceCardConfig card = DeviceCardConfig(
      label: '灯光状态',
      mainFmt: '{v}',
      subTpl: '{state}',
      icon: '☀',
      color: '#facc15',
      layout: layout,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 120,
            child: JsonCardRenderer(
              group: group,
              card: card,
              typeKey: 'light',
              onOpenDetail: () {},
              onAction: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('☀'), findsOneWidget, reason: '符号图标应直接绘制字符');
    expect(find.byIcon(Icons.circle), findsNothing, reason: '不应再回退成实心圆');
  });

  test('图片图标路径解析：相对路径按 serverBaseUrl 拼接，符号不误判', () {
    final String oldBase = HaConfig.envServerBaseUrl;
    HaConfig.envServerBaseUrl = 'http://localhost:3000/';
    try {
      expect(
        CachedCardIcon.resolveUrl('/api/files/f_123/avatar'),
        'http://localhost:3000/api/files/f_123/avatar',
      );
      expect(
        CachedCardIcon.resolveUrl('https://cdn.example.com/icon.webp'),
        'https://cdn.example.com/icon.webp',
      );
      expect(CachedCardIcon.resolveUrl('☀'), isNull);
      expect(CachedCardIcon.resolveUrl('lightbulb'), isNull);
    } finally {
      HaConfig.envServerBaseUrl = oldBase;
    }
  });

  test('CardEvalContext 按实体 id 后缀取值 + room 占位符', () {
    final HaDeviceGroup group = HaDeviceGroup(
      deviceId: 'dev_kettle',
      title: '米家智能电热水瓶 5L',
      entities: <HaEntityStateModel>[
        _entity('switch.kettle_auto_keep_warm_p_2_7', 'on', name: '保温'),
        _entity('sensor.kettle_status_p_2_1', '保温中…', name: '工作状态'),
        _entity('select.kettle_mode_p_2_3', '自来水', name: '模式'),
        _entity('number.kettle_target_temperature_p_2_5', '100', name: '设定温度'),
      ],
    );
    const DeviceCardConfig card = DeviceCardConfig(
      label: '当前温度',
      mainFmt: '{v}°C',
      subTpl: '{s1} · {s2}',
      icon: 'water_drop',
      color: '#2dd4bf',
      mainEntity: '_temperature_p_2_6',
    );
    final CardEvalContext ctx = CardEvalContext(
      group: group,
      card: card,
      areaLabel: '客厅',
    );
    expect(
      ctx.resolve('{room} · {s:_status_p_2_1} · {s:_mode_p_2_3}'),
      '客厅 · 保温中… · 自来水',
    );
    expect(
      ctx.resolve('toggle@{id:_auto_keep_warm_p_2_7}'),
      'toggle@switch.kettle_auto_keep_warm_p_2_7',
    );
    expect(ctx.resolve('目标 {s:_target_temperature_p_2_5}°C'), '目标 100°C');
  });

  test('占位符内联映射与亮度百分比：一行里不同实体各用各的 on/off 文案', () {
    final HaDeviceGroup group = HaDeviceGroup(
      deviceId: 'dev_aroma',
      title: '米家智能香氛机 氛围灯',
      entities: <HaEntityStateModel>[
        _entity('switch.xw002_on_p_2_2', 'on', name: '香薰机开关'),
        _entity('light.xw002_s_3_ambient_light', 'on', name: '氛围灯'),
        _entity('sensor.xw002_battery_level_p_5_1', '25', name: '电量'),
      ],
    );
    // 氛围灯带 brightness 属性（HA 0-255）。
    final List<HaEntityStateModel> ents = List<HaEntityStateModel>.from(group.entities);
    ents[1] = HaEntityStateModel(
      entityId: 'light.xw002_s_3_ambient_light',
      state: 'on',
      attributes: <String, dynamic>{'brightness': 82},
    );
    final HaDeviceGroup withBright = HaDeviceGroup(
      deviceId: group.deviceId, title: group.title, entities: ents,
    );
    const DeviceCardConfig card = DeviceCardConfig(label: '香氛机');
    final CardEvalContext ctx = CardEvalContext(group: withBright, card: card);

    // 同一行：开关用「已开机/待机中」，氛围灯用「已开启/已关闭」，亮度 82→32%。
    expect(
      ctx.resolve(
        '{s:_on_p_2_2|on=已开机,off=待机中} · 氛围灯'
        '{s:_s_3_ambient_light|on=已开启,off=已关闭}'
        '({s:_s_3_ambient_light.brightness|pct}%) · 电量 {s:_battery_level_p_5_1}%',
      ),
      '已开机 · 氛围灯已开启(32%) · 电量 25%',
    );
    // s: 前缀点号读属性（不写 pct 则给原始 0-255）。
    expect(ctx.resolve('{s:_s_3_ambient_light.brightness}'), '82');
    // 电量本身已是百分数，直接显示、不要套 pct。
    expect(ctx.resolve('{s:_battery_level_p_5_1}%'), '25%');

    // 亮度段只在氛围灯 on 时显示：用 state 内联映射输出左右括号，off 时给空串。
    const tpl = '{s:_on_p_2_2|on=已开机,off=待机中} · 氛围灯'
      '{s:_s_3_ambient_light|on=已开启,off=已关闭}'
      '{s:_s_3_ambient_light|on=(,off=}'
      '{s:_s_3_ambient_light.brightness|pct}'
      '{s:_s_3_ambient_light|on=%),off=} · 电量 {s:_battery_level_p_5_1}%';
    expect(ctx.resolve(tpl), '已开机 · 氛围灯已开启(32%) · 电量 25%');

    // 关灯：brightness 属性不存在，整段括号+数值消失。
    final HaDeviceGroup off = HaDeviceGroup(
      deviceId: group.deviceId, title: group.title,
      entities: <HaEntityStateModel>[
        _entity('switch.xw002_on_p_2_2', 'off', name: '香薰机开关'),
        _entity('light.xw002_s_3_ambient_light', 'off', name: '氛围灯'),
        _entity('sensor.xw002_battery_level_p_5_1', '25', name: '电量'),
      ],
    );
    final CardEvalContext offCtx = CardEvalContext(group: off, card: card);
    expect(offCtx.resolve(tpl), '待机中 · 氛围灯已关闭 · 电量 25%');
  });

  test('占位符 date 规则：ISO 时间按 DateFormat pattern/locale 格式化', () {
    final HaDeviceGroup group = HaDeviceGroup(
      deviceId: 'dev_ws',
      title: '双键无线开关',
      entities: <HaEntityStateModel>[
        _entity(
          'event.yeelink_cn_blt_3_1i1e48ak4co00_contrl_click_e_3_1012',
          '2026-11-23T15:11:06.640',
          name: '单击',
        ),
      ],
    );
    const DeviceCardConfig card = DeviceCardConfig(label: '双键');
    final CardEvalContext ctx = CardEvalContext(group: group, card: card);
    final String token = '{s:click_e_3_1012';

    // 简写名（同 DateFormat.yMd('zh')）/ Hms。
    expect(ctx.resolve('$token|date:yMd}'), '2026/11/23');
    expect(ctx.resolve('$token|date:yMEd}'), '2026/11/23周一');
    expect(ctx.resolve('$token|date:Hms}'), '15:11:06');
    // 自定义 pattern（冒号后即 pattern，locale 默认 zh）。
    expect(ctx.resolve('$token|date:yyyy-MM-dd HH:mm}'), '2026-11-23 15:11');
    // locale 前缀：zh / en_US。
    expect(ctx.resolve('$token|date:zh:yMd}'), '2026/11/23');
    expect(ctx.resolve('$token|date:en_US:yMd}'), '11/23/2026');
    // 非时间值（off/unknown）原样返回，便于再用映射转占位符。
    final HaDeviceGroup unknown = HaDeviceGroup(
      deviceId: 'dev_ws',
      title: '单键无线开关',
      entities: <HaEntityStateModel>[
        _entity('event.lumi_cn_blt_3_mcn001_click_e_3_1012', 'unknown', name: '单击'),
      ],
    );
    final CardEvalContext unknownCtx = CardEvalContext(group: unknown, card: card);
    expect(
      unknownCtx.resolve('{s:click_e_3_1012|date:yMd,unknown=—}'),
      '—',
    );
  });

  test('占位符 date 规则：带 +00:00 的 ISO 时间按本地时区显示', () {
    const String raw = '2026-11-24T12:09:10.156+00:00';
    final HaDeviceGroup group = HaDeviceGroup(
      deviceId: 'dev_ws2',
      title: '双键无线开关',
      entities: <HaEntityStateModel>[
        _entity('event.wireless_click_e_3_1012', raw, name: '单击'),
      ],
    );
    const DeviceCardConfig card = DeviceCardConfig(label: '双键');
    final CardEvalContext ctx = CardEvalContext(group: group, card: card);

    final DateTime local = DateTime.parse(raw).toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    final String expected = '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
    final String resolved = ctx.resolve('{s:wireless_click_e_3_1012|date:yyyy-MM-dd HH:mm}');
    expect(resolved, expected);
    if (local.timeZoneOffset != Duration.zero) {
      expect(resolved, isNot('2026-11-24 12:09'));
    }
  });

  test('占位符 maxWith + ago：取接入/断开中较晚的时间并显示相对时间', () {
    final DateTime now = DateTime.now().toUtc();
    // 接入更早、断开更晚 → 副标题应显示断开时间。
    final HaDeviceGroup group = HaDeviceGroup(
      deviceId: 'dev_router',
      title: 'Potatokid',
      entities: <HaEntityStateModel>[
        _entity(
          'event.xiaomi_cn_rd08_device_connect_e_2_1',
          now.subtract(const Duration(minutes: 52, seconds: 5)).toIso8601String(),
          name: '路由器 设备接入',
        ),
        _entity(
          'event.xiaomi_cn_rd08_device_disconnect_e_2_2',
          now.subtract(const Duration(minutes: 10, seconds: 5)).toIso8601String(),
          name: '路由器 设备断开',
        ),
      ],
    );
    const DeviceCardConfig card = DeviceCardConfig(label: '运行状态');
    final CardEvalContext ctx = CardEvalContext(group: group, card: card);
    expect(
      ctx.resolve(
        '{s:_device_connect_e_2_1|maxWith=s:_device_disconnect_e_2_2,ago}',
      ),
      '10分钟前',
    );

    // 两台路由器中不支持的那台报 unknown → 映射成 —，不裸显 unknown。
    final HaDeviceGroup unknown = HaDeviceGroup(
      deviceId: 'dev_router_rd03',
      title: 'Potatokid',
      entities: <HaEntityStateModel>[
        _entity('event.xiaomi_cn_rd03_device_connect_e_2_1', 'unknown'),
        _entity('event.xiaomi_cn_rd03_device_disconnect_e_2_2', 'unknown'),
      ],
    );
    expect(
      CardEvalContext(group: unknown, card: card).resolve(
        '{s:_device_connect_e_2_1|maxWith=s:_device_disconnect_e_2_2,ago,unknown=—}',
      ),
      '—',
    );
  });

  test('占位符 when=：另一实体状态命中时覆盖文案（香薰机充电中）', () {
    const DeviceCardConfig card = DeviceCardConfig(label: '当前值');
    final HaDeviceGroup charging = HaDeviceGroup(
      deviceId: 'dev_aroma',
      title: '米家智能香氛机',
      entities: <HaEntityStateModel>[
        _entity('switch.xiaomi_cn_xw002_on_p_2_2', 'on'),
        _entity('sensor.xiaomi_cn_xw002_charging_state_p_5_2', 'Charging'),
        _entity('sensor.xiaomi_cn_xw002_battery_level_p_5_1', '45'),
      ],
    );
    final CardEvalContext ctx = CardEvalContext(group: charging, card: card);
    // 副标题：开机文案在充电时被覆盖为「充电中」。
    expect(
      ctx.resolve('{s:_on_p_2_2|on=已开机,off=待机中,when=s:_charging_state_p_5_2:Charging=充电中}'),
      '充电中',
    );
    // 大字行：电量标签按充电状态切换。
    expect(
      ctx.resolve('{s:_charging_state_p_5_2|Charging=充电中,Not Charging=电量,Not Chargeable=电量} {s:_battery_level_p_5_1}%'),
      '充电中 45%',
    );

    // 未在充电：保留开机文案，电量标签显示「电量」。
    final HaDeviceGroup idle = HaDeviceGroup(
      deviceId: 'dev_aroma_idle',
      title: '米家智能香氛机',
      entities: <HaEntityStateModel>[
        _entity('switch.xiaomi_cn_xw002_on_p_2_2', 'on'),
        _entity('sensor.xiaomi_cn_xw002_charging_state_p_5_2', 'Not Charging'),
        _entity('sensor.xiaomi_cn_xw002_battery_level_p_5_1', '45'),
      ],
    );
    final CardEvalContext idleCtx = CardEvalContext(group: idle, card: card);
    expect(
      idleCtx.resolve('{s:_on_p_2_2|on=已开机,off=待机中,when=s:_charging_state_p_5_2:Charging=充电中}'),
      '已开机',
    );
    expect(
      idleCtx.resolve('{s:_charging_state_p_5_2|Charging=充电中,Not Charging=电量,Not Chargeable=电量} {s:_battery_level_p_5_1}%'),
      '电量 45%',
    );
  });

  testWidgets('热水瓶走后台 JSON 布局：fill 上下分布 + 大号 chip + kettle@action 回调', (
    WidgetTester tester,
  ) async {
    final HaDeviceGroup group = HaDeviceGroup(
      deviceId: 'dev_kettle',
      title: '米家智能电热水瓶 5L',
      entities: <HaEntityStateModel>[
        _entity('sensor.kettle_temperature_p_2_6', '55', name: '温度'),
        _entity('sensor.kettle_status_p_2_1', '待机中…', name: '工作状态'),
        _entity('select.kettle_mode_p_2_3', '自来水', name: '模式'),
        _entity('number.kettle_target_temperature_p_2_5', '100', name: '设定温度'),
      ],
    );
    const DeviceCardConfig card = DeviceCardConfig(
      label: '当前温度',
      mainFmt: '{v}°C',
      subTpl: '{s1} · {s2}',
      icon: 'water_drop',
      color: '#2dd4bf',
      mainEntity: '_temperature_p_2_6',
      layout: CardLayoutNode(
        type: 'column',
        fill: true,
        mainAlign: 'spaceBetween',
        padding: <double>[12, 10],
        children: <CardLayoutNode>[
          CardLayoutNode(type: 'text', value: '{title}', size: 15),
          CardLayoutNode(
            type: 'row',
            mainAlign: 'spaceBetween',
            crossAlign: 'end',
            children: <CardLayoutNode>[
              CardLayoutNode(
                type: 'text',
                value: '{main}',
                size: 38,
                weight: 700,
              ),
              CardLayoutNode(
                type: 'chip',
                label: '{s:_status_p_2_1}',
                onClick: 'kettle@action',
                size: 15,
                height: 42,
                map: '待机中…=加热,烧水中…=停止加热',
              ),
            ],
          ),
        ],
      ),
    );
    final List<String> actions = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 188,
            child: JsonCardRenderer(
              group: group,
              card: card,
              typeKey: 'kettle',
              areaLabel: '客厅',
              onAction: actions.add,
              onOpenDetail: () {},
            ),
          ),
        ),
      ),
    );

    // map 值替换 + kettle 专用动作通道由后台 JSON 驱动。
    expect(find.text('加热'), findsOneWidget);
    expect(find.text('55°C'), findsOneWidget);
    final SizedBox chipBox = tester.widget<SizedBox>(
      find.ancestor(of: find.text('加热'), matching: find.byType(SizedBox)).first,
    );
    expect(chipBox.height, 42);
    final Text chipText = tester.widget<Text>(find.text('加热'));
    expect(chipText.style?.fontSize, 15);

    await tester.tap(find.text('加热'));
    await tester.pump();
    expect(actions, <String>['kettle@action']);
  });

  testWidgets('普通插座布局：状态行 + 大圆按钮 + expand 功率曲线撑满不溢出', (
    WidgetTester tester,
  ) async {
    final HaDeviceGroup group = HaDeviceGroup(
      deviceId: 'dev_socket',
      title: '客厅插座',
      entities: <HaEntityStateModel>[
        _entity('switch.cuco_v3_on_p_2_1', 'on', name: '插座'),
        _entity('sensor.cuco_v3_electric_power_p_11_2', '24', name: '功率'),
      ],
    );
    final CardLayoutNode layout = CardLayoutNode.fromJson(<String, dynamic>{
      'type': 'column',
      'fill': true,
      'gap': 8,
      'padding': <dynamic>[12, 10],
      'children': <dynamic>[
        <String, dynamic>{
          'type': 'row',
          'gap': 10,
          'crossAlign': 'center',
          'children': <dynamic>[
            <String, dynamic>{
              'type': 'icon',
              'value': '⏻',
              'size': 24,
              'box': <String, dynamic>{
                'size': 46,
                'radius': 12,
                'bg': '#4dd4ac26',
                'color': '#4dd4ac',
              },
            },
            <String, dynamic>{
              'type': 'column',
              'expand': true,
              'gap': 2,
              'children': <dynamic>[
                <String, dynamic>{
                  'type': 'text',
                  'value': '{title}',
                  'size': 14,
                  'weight': 600,
                  'maxLines': 1,
                },
                <String, dynamic>{
                  'type': 'text',
                  'value': '{s:_on_p_2_1}',
                  'map': 'on=开启,off=关闭',
                  'size': 12,
                  'color': '#4dd4ac',
                  'maxLines': 1,
                },
              ],
            },
            <String, dynamic>{
              'type': 'button',
              'round': true,
              'value': 'power_settings_new',
              'size': 52,
              'color': '#4dd4ac',
              'onClick': 'toggle@{id:_on_p_2_1}',
            },
          ],
        },
        <String, dynamic>{
          'type': 'sparkline',
          'metric': 'power',
          'expand': true,
          'color': '#4dd4ac',
          'showLabels': false,
        },
      ],
    });
    final DeviceCardConfig card = DeviceCardConfig(
      label: '开关状态',
      color: '#4dd4ac',
      layout: layout,
    );
    final List<String> actions = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 188,
            child: JsonCardRenderer(
              group: group,
              card: card,
              typeKey: 'socket',
              onOpenDetail: () {},
              onAction: actions.add,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 状态行 map：on→开启；圆按钮与 expand sparkline 都渲染、不溢出。
    expect(find.text('开启'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    expect(actions, <String>['toggle@switch.cuco_v3_on_p_2_1']);
  });

  testWidgets('插座圆按钮按状态互斥显隐：开=红橙，关=绿', (WidgetTester tester) async {
    // 两个圆按钮放在 gap=0 的子行里，用 visibleWhen 按 state 互斥：
    // on 时只渲染红橙按钮，off 时只渲染绿按钮，位置不变。
    CardLayoutNode slot() => CardLayoutNode.fromJson(<String, dynamic>{
          'type': 'row',
          'gap': 0,
          'crossAlign': 'center',
          'children': <dynamic>[
            <String, dynamic>{
              'type': 'button',
              'round': true,
              'value': 'power_settings_new',
              'size': 52,
              'color': '#FF7043',
              'onClick': 'toggle@{id:_on_p_2_1}',
              'visibleWhen': '{s:_on_p_2_1}=on',
            },
            <String, dynamic>{
              'type': 'button',
              'round': true,
              'value': 'power_settings_new',
              'size': 52,
              'color': '#4dd4ac',
              'onClick': 'toggle@{id:_on_p_2_1}',
              'visibleWhen': '{s:_on_p_2_1}=off',
            },
          ],
        });
    final DeviceCardConfig card = DeviceCardConfig(
      label: '开关状态',
      color: '#4dd4ac',
      layout: slot(),
    );

    Future<void> pumpWithState(String state) async {
      final HaDeviceGroup group = HaDeviceGroup(
        deviceId: 'dev_socket',
        title: '客厅插座',
        entities: <HaEntityStateModel>[
          _entity('switch.cuco_v3_on_p_2_1', state, name: '插座'),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 120,
              height: 80,
              child: JsonCardRenderer(
                group: group,
                card: card,
                typeKey: 'socket',
                onOpenDetail: () {},
                onAction: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    // 开：只剩一个按钮（红橙），另一个被 visibleWhen 隐掉。
    await pumpWithState('on');
    expect(find.byType(FilledButton), findsOneWidget);
    Color onColor() => tester.widget<FilledButton>(find.byType(FilledButton))
            .style!
            .foregroundColor!
            .resolve(<WidgetState>{})!;
    expect(onColor(), const Color(0xFFFF7043));

    // 关：同样只剩一个按钮（绿）。
    await pumpWithState('off');
    expect(find.byType(FilledButton), findsOneWidget);
    expect(onColor(), const Color(0xFF4DD4AC));
    expect(tester.takeException(), isNull);
  });

  test('parseReplaceMap 解析子串替换表（含引号包裹与全角等号）', () {
    final Map<String, String>? r = CardEvalContext.parseReplaceMap(
      '小米米家智能开关（双开单控）=\'含,逗号\'；A＝B\n空=',
    );
    expect(r, isNotNull);
    expect(r!['小米米家智能开关（双开单控）'], '含,逗号');
    expect(r['A'], 'B');
    expect(r['空'], '');
    expect(CardEvalContext.parseReplaceMap(''), isNull);
  });

  test('replace 子串替换：删前缀 / 替换任意字符 / 与 map 组合 / 不影响条件', () {
    final HaDeviceGroup group = HaDeviceGroup(
      deviceId: 'dev_switch',
      title: '客厅 双开',
      entities: <HaEntityStateModel>[
        _entity(
          'switch.zimi_on_p_2_1',
          'off',
          name: '小米米家智能开关（双开单控）  客厅灯 左键',
        ),
      ],
    );
    const DeviceCardConfig card = DeviceCardConfig(subTpl: '{state}');
    final CardEvalContext ctx = CardEvalContext(group: group, card: card);
    final Map<String, String> friendly = CardEvalContext.parseReplaceMap(
      '小米米家智能开关（双开单控）=',
    )!;
    final Map<String, String> both = CardEvalContext.parseReplaceMap(
      '小米米家智能开关（双开单控）=/任意/',
    )!;
    final Map<String, String> stateMap = <String, String>{'on': '开', 'off': '关'};

    // 删子串：去掉冗长设备型号前缀，保留 "  客厅灯 左键"
    expect(
      ctx.resolve('{a:_p_2_1.friendly_name}', null, friendly),
      '  客厅灯 左键',
    );
    // 替换成任意字符（含符号）
    expect(
      ctx.resolve('{a:_p_2_1.friendly_name}', null, both),
      '/任意/  客厅灯 左键',
    );
    // 子串替换 + 整值 map 组合：先删前缀再状态 on/off→开/关
    expect(
      ctx.resolve(
        '{a:_p_2_1.friendly_name}:{s:_p_2_1}',
        stateMap,
        friendly,
      ),
      '  客厅灯 左键:关',
    );
    // 条件判断不传 replace/map，仍基于原始 state
    expect(ctx.evalCondition('{s:_p_2_1} = off'), isTrue);
    expect(ctx.resolve('{s:_p_2_1}'), 'off');
  });

  test('指标曲线查询 key 与采样器写入 key 一致', () {
    // 回归：采样器按裸 deviceId 写入，orderKey 带 device: 前缀，
    // 之前曲线用 orderKey 查，永远拿到空列表（只剩空网格）。
    final HaDeviceGroup group = HaDeviceGroup(
      deviceId: 'dev_socket_781',
      title: '厨房插座',
      entities: <HaEntityStateModel>[
        _entity('switch.cuco_v3_on_p_2_1', 'on'),
      ],
    );
    expect(group.orderKey, 'device:dev_socket_781');
    expect(group.metricDeviceId, 'dev_socket_781');

    final MetricHistoryStore store = MetricHistoryStore();
    store.record(group.metricDeviceId, Metric.power, 24);
    expect(store.watch(group.metricDeviceId, Metric.power).value, hasLength(1));
    expect(store.watch(group.orderKey, Metric.power).value, isEmpty);
  });

  // ---- 条件属性（colorMap/labelMap/iconMap）与 stack 叠放 ----
  Future<void> pumpLayout(
    WidgetTester tester,
    String switchState,
    Map<String, dynamic> layoutJson,
  ) async {
    final HaDeviceGroup group = HaDeviceGroup(
      deviceId: 'dev_x',
      title: '测试设备',
      entities: <HaEntityStateModel>[
        _entity('switch.x_on_p_2_1', switchState, name: '开关'),
      ],
    );
    final DeviceCardConfig card = DeviceCardConfig(
      label: '开关',
      color: '#4dd4ac',
      layout: CardLayoutNode.fromJson(layoutJson),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            height: 120,
            child: JsonCardRenderer(
              group: group,
              card: card,
              typeKey: 'switch',
              onOpenDetail: () {},
              onAction: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('colorMap 让同一个按钮按状态变色（开红橙/关绿）', (WidgetTester tester) async {
    final Map<String, dynamic> layout = <String, dynamic>{
      'type': 'row',
      'children': <dynamic>[
        <String, dynamic>{
          'type': 'button',
          'round': true,
          'value': 'power_settings_new',
          'size': 52,
          'color': '{s:_on_p_2_1}',
          'colorMap': 'on=#FF7043,off=#4dd4ac',
          'onClick': 'toggle@{id:_on_p_2_1}',
        },
      ],
    };
    Color btnColor() => tester.widget<FilledButton>(find.byType(FilledButton))
            .style!.foregroundColor!.resolve(<WidgetState>{})!;

    await pumpLayout(tester, 'on', layout);
    expect(find.byType(FilledButton), findsOneWidget);
    expect(btnColor(), const Color(0xFFFF7043));

    await pumpLayout(tester, 'off', layout);
    expect(btnColor(), const Color(0xFF4DD4AC));
  });

  testWidgets('labelMap/iconMap 按状态改文案与图标', (WidgetTester tester) async {
    final Map<String, dynamic> layout = <String, dynamic>{
      'type': 'column',
      'children': <dynamic>[
        <String, dynamic>{
          'type': 'button',
          'label': '{s:_on_p_2_1}',
          'labelMap': 'on=关闭,off=开启',
          'icon': '{s:_on_p_2_1}',
          'iconMap': 'on=power_off,off=power_on',
          'color': '#4dd4ac',
          'onClick': 'toggle@{id:_on_p_2_1}',
        },
      ],
    };
    await pumpLayout(tester, 'on', layout);
    expect(find.text('关闭'), findsOneWidget);
    expect(find.text('开启'), findsNothing);

    await pumpLayout(tester, 'off', layout);
    expect(find.text('开启'), findsOneWidget);
    expect(find.text('关闭'), findsNothing);
  });

  testWidgets('stack 叠放：背景与前景同槽渲染不溢出', (WidgetTester tester) async {
    final Map<String, dynamic> layout = <String, dynamic>{
      'type': 'stack',
      'children': <dynamic>[
        <String, dynamic>{
          'type': 'text',
          'value': '背景',
          'size': 20,
          'color': '#336699',
          'stackAlign': 'center',
        },
        <String, dynamic>{
          'type': 'text',
          'value': '角标',
          'size': 10,
          'color': '#FF7043',
          'stackAlign': 'topRight',
        },
      ],
    };
    await pumpLayout(tester, 'on', layout);
    expect(find.text('背景'), findsOneWidget);
    expect(find.text('角标'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('enabledWhen 关机时按钮显示但禁用（不可点），开机时可点', (WidgetTester tester) async {
    final Map<String, dynamic> layout = <String, dynamic>{
      'type': 'column',
      'children': <dynamic>[
        <String, dynamic>{
          'type': 'chip',
          'label': '快速出香',
          'color': '{s:_on_p_2_1}',
          'colorMap': 'on=#fb923c,off=#6b7280',
          'enabledWhen': '{s:_on_p_2_1}=on',
          'onClick': 'press@{id:_on_p_2_1}',
        },
      ],
    };
    // 关机：节点仍在，但 OutlinedButton.onPressed == null（禁用）。
    await pumpLayout(tester, 'off', layout);
    expect(find.text('快速出香'), findsOneWidget);
    OutlinedButton offBtn = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, '快速出香'));
    expect(offBtn.onPressed, isNull);
    // 开机：同位置按钮可点。
    await pumpLayout(tester, 'on', layout);
    expect(find.text('快速出香'), findsOneWidget);
    OutlinedButton onBtn = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, '快速出香'));
    expect(onBtn.onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  test('DeviceCardConfig 解析后台下发的 bg / disabledBg', () {
    final DeviceCardConfig card = DeviceCardConfig.fromJson(<String, dynamic>{
      'bg': '#232830',
      'disabledBg': '#171a1f',
    });
    expect(card.bg, '#232830');
    expect(card.disabledBg, '#171a1f');
    expect(DeviceCardConfig.fromJson(<String, dynamic>{}).bg, '');
  });

  testWidgets('卡片背景可被 card.bg 覆盖，文本换行自动放开 maxLines', (WidgetTester tester) async {
    final HaDeviceGroup group = HaDeviceGroup(
      deviceId: 'dev_bg',
      title: '背景测试',
      entities: <HaEntityStateModel>[
        _entity('switch.bg_on_p_2_1', 'on', name: '开关'),
      ],
    );
    final DeviceCardConfig card = DeviceCardConfig(
      bg: '#232830',
      layout: CardLayoutNode.fromJson(<String, dynamic>{
        'type': 'column',
        'children': <dynamic>[
          <String, dynamic>{'type': 'text', 'value': '第一行\n第二行'},
        ],
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            height: 120,
            child: JsonCardRenderer(
              group: group,
              card: card,
              typeKey: 'switch',
              onOpenDetail: () {},
              onAction: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final Card rendered = tester.widget<Card>(find.byType(Card).first);
    expect(rendered.color, const Color(0xFF232830));
    final Text multiline = tester.widget<Text>(find.text('第一行\n第二行'));
    expect(multiline.maxLines, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('空调 1×2 交互卡：电源/温湿度/目标温度/模式/三个快捷开关正确渲染', (
    WidgetTester tester,
  ) async {
    final HaEntityStateModel ac = HaEntityStateModel(
      entityId: 'climate.xiaomi_cn_735376016_m9',
      state: 'off',
      attributes: <String, dynamic>{
        'friendly_name': '小米空调巨省电 1.5匹  空调',
        'current_temperature': 22.0,
        'current_humidity': 42,
        'temperature': 26.5,
        'fan_mode': '二档',
        'hvac_modes': <String>['cool', 'dry', 'fan_only', 'heat', 'off'],
        'fan_modes': <String>['自动', '一档', '二档', 'Max档'],
      },
    );
    final HaDeviceGroup group = HaDeviceGroup(
      deviceId: 'dev_ac',
      title: '卧室 小米空调巨省电',
      entities: <HaEntityStateModel>[
        ac,
        _entity('switch.xiaomi_cn_735376016_m9_eco_p_2_7', 'off', name: 'ECO节能模式'),
        _entity('switch.xiaomi_cn_735376016_m9_sleep_mode_p_2_11', 'off', name: '标准睡眠'),
        _entity('switch.xiaomi_cn_735376016_m9_un_straight_blowing_p_2_15', 'off', name: '防直吹'),
      ],
    );
    // 用服务端默认布局（与 deviceTypes.js CARD_LAYOUTS.climate 一致）。
    final CardLayoutNode layout = CardLayoutNode.fromJson(
      _acLayoutJson(),
    );
    final DeviceCardConfig card = DeviceCardConfig(
      label: '当前室温', mainAttr: 'current_temperature', mainFmt: '{v}°C',
      subTpl: '{s1} · 目标 {s2}°C', icon: '❄', color: '#2f9cff',
      layout: layout,
    );
    final List<String> actions = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 780,
            height: 200,
            child: JsonCardRenderer(
              group: group,
              card: card,
              typeKey: 'climate',
              onOpenDetail: () {},
              onAction: actions.add,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // 主实体是 climate，{attr.*} 与 {state} 都应取到它的属性而非下游 switch。
    expect(find.textContaining('22'), findsWidgets); // 当前温度
    expect(find.text('26.5°C'), findsOneWidget); // 目标温度，不再是 on°C
    expect(find.text('已关闭 · 湿度 42%'), findsOneWidget);
    expect(find.text('风速'), findsOneWidget); // 风速 ± 步进区标题
    expect(find.text('二档'), findsNWidgets(2)); // 步进区当前档 + 底部风速 chip
    expect(find.text('节能'), findsOneWidget);
    expect(find.text('睡眠'), findsOneWidget);
    expect(find.text('防直吹'), findsOneWidget);
    // 关机时温度 ± / 风速 ± / 模式 / 风速 chip 都不可点；只有电源键可点。
    await tester.tap(find.text('+').last); // 风速 +
    await tester.pump();
    expect(actions, isEmpty);
    await tester.tap(find.text('已关闭')); // 底部模式 chip（关机时显示「已关闭」）
    await tester.pump();
    expect(actions, isEmpty);
    expect(find.byIcon(Icons.power_settings_new), findsOneWidget);
    await tester.tap(find.byIcon(Icons.power_settings_new));
    await tester.pump();
    expect(actions, <String>['toggle@climate.xiaomi_cn_735376016_m9']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('空调开机时风速 ± 按 fan_modes 索引下发档位，关机时禁用', (
    WidgetTester tester,
  ) async {
    final HaEntityStateModel ac = HaEntityStateModel(
      entityId: 'climate.bedroom',
      state: 'cool',
      attributes: <String, dynamic>{
        'friendly_name': '卧室空调',
        'current_temperature': 24.0,
        'current_humidity': 50,
        'temperature': 26.0,
        'fan_mode': '二档',
        'hvac_modes': <String>['cool', 'dry', 'fan_only', 'heat', 'off'],
        'fan_modes': <String>['自动', '一档', '二档', '三档', 'Max档'],
      },
    );
    final HaDeviceGroup group = HaDeviceGroup(
      deviceId: 'dev_ac_on',
      title: '卧室空调',
      entities: <HaEntityStateModel>[ac],
    );
    final DeviceCardConfig card = DeviceCardConfig(
      label: '当前室温', mainAttr: 'current_temperature', mainFmt: '{v}°C',
      icon: '❄', color: '#2f9cff', layout: CardLayoutNode.fromJson(_acLayoutJson()),
    );
    final List<String> actions = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 780,
            height: 200,
            child: JsonCardRenderer(
              group: group, card: card, typeKey: 'climate',
              onOpenDetail: () {}, onAction: actions.add,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // 两个「−」：目标温度与风速；第 2 个是风速减档。
    expect(find.text('−'), findsNWidgets(2));
    await tester.tap(find.text('−').last);
    await tester.pump();
    expect(actions, contains('climateFan@climate.bedroom:-1'));
    await tester.tap(find.text('+').last);
    await tester.pump();
    expect(actions, contains('climateFan@climate.bedroom:+1'));
    expect(tester.takeException(), isNull);
  });
}

/// 与 deviceTypes.js CARD_LAYOUTS.climate 对齐的布局 JSON（测试用）。
Map<String, dynamic> _acLayoutJson() => <String, dynamic>{
  'type': 'column',
  'fill': true,
  'gap': 8,
  'padding': <double>[12, 10],
  'children': <Map<String, dynamic>>[
    <String, dynamic>{
      'type': 'row', 'gap': 10, 'crossAlign': 'center',
      'children': <Map<String, dynamic>>[
        <String, dynamic>{
          'type': 'icon', 'value': '{icon}', 'size': 24,
          'box': <String, dynamic>{'size': 42, 'radius': 12, 'bg': '{color}26', 'color': '{color}'},
        },
        <String, dynamic>{
          'type': 'column', 'expand': true, 'gap': 2,
          'children': <Map<String, dynamic>>[
            <String, dynamic>{'type': 'text', 'value': '{title}', 'size': 14, 'weight': 700, 'maxLines': 1},
            <String, dynamic>{'type': 'text', 'value': '{state|cool=制冷,dry=除湿,fan_only=送风,heat=制热,off=已关闭,auto=自动} · 湿度 {attr.current_humidity}%', 'size': 12, 'color': '{color}', 'maxLines': 1},
          ],
        },
        <String, dynamic>{
          'type': 'chip', 'round': true, 'icon': 'power_settings_new', 'size': 40,
          'style': '{state|off=normal,on=active}', 'color': '{color}',
          'onClick': 'toggle@{primary.entityId}',
        },
      ],
    },
    <String, dynamic>{
      'type': 'row', 'gap': 8, 'crossAlign': 'center',
      'children': <Map<String, dynamic>>[
        <String, dynamic>{
          'type': 'column', 'gap': 1, 'expand': true,
          'children': <Map<String, dynamic>>[
            <String, dynamic>{'type': 'text', 'value': '当前温度', 'size': 11, 'color': 'outline', 'maxLines': 1},
            <String, dynamic>{'type': 'text', 'value': '{attr.current_temperature}°C', 'size': 28, 'weight': 700, 'color': '{color}', 'maxLines': 1},
          ],
        },
        <String, dynamic>{
          'type': 'column', 'gap': 1, 'crossAlign': 'center',
          'children': <Map<String, dynamic>>[
            <String, dynamic>{'type': 'text', 'value': '目标温度', 'size': 11, 'color': 'outline', 'maxLines': 1},
            <String, dynamic>{
              'type': 'row', 'gap': 4, 'crossAlign': 'center',
              'children': <Map<String, dynamic>>[
                <String, dynamic>{'type': 'chip', 'label': '−', 'size': 16, 'height': 34, 'enabledWhen': '{state}!=off', 'onClick': 'climateTemp@{primary.entityId}:-0.5'},
                <String, dynamic>{'type': 'text', 'value': '{attr.temperature}°C', 'size': 20, 'weight': 700, 'color': '{color}', 'maxLines': 1},
                <String, dynamic>{'type': 'chip', 'label': '+', 'size': 16, 'height': 34, 'enabledWhen': '{state}!=off', 'onClick': 'climateTemp@{primary.entityId}:+0.5'},
              ],
            },
          ],
        },
        <String, dynamic>{
          'type': 'column', 'gap': 1, 'crossAlign': 'center',
          'children': <Map<String, dynamic>>[
            <String, dynamic>{'type': 'text', 'value': '风速', 'size': 11, 'color': '#EF8CD1', 'maxLines': 1},
            <String, dynamic>{
              'type': 'row', 'gap': 4, 'crossAlign': 'center',
              'children': <Map<String, dynamic>>[
                <String, dynamic>{'type': 'chip', 'label': '−', 'size': 16, 'height': 34, 'enabledWhen': '{state}!=off', 'onClick': 'climateFan@{primary.entityId}:-1'},
                <String, dynamic>{'type': 'text', 'value': '{attr.fan_mode}', 'size': 15, 'weight': 700, 'color': '#EF8CD1', 'maxLines': 1},
                <String, dynamic>{'type': 'chip', 'label': '+', 'size': 16, 'height': 34, 'enabledWhen': '{state}!=off', 'onClick': 'climateFan@{primary.entityId}:+1'},
              ],
            },
          ],
        },
      ],
    },
    <String, dynamic>{
      'type': 'wrap', 'gap': 6,
      'children': <Map<String, dynamic>>[
        <String, dynamic>{'type': 'chip', 'label': '{state|cool=制冷,dry=除湿,fan_only=送风,heat=制热,off=已关闭,auto=自动}', 'size': 12, 'height': 28, 'color': '{color}', 'enabledWhen': '{state}!=off', 'onClick': 'climateMode@{primary.entityId}'},
        <String, dynamic>{'type': 'chip', 'label': '{attr.fan_mode}', 'size': 12, 'height': 28, 'color': '{color}', 'enabledWhen': '{state}!=off', 'onClick': 'climateFan@{primary.entityId}'},
        <String, dynamic>{'type': 'chip', 'label': '{s:_eco_p_2_7|on=✓ 节能,off=节能}', 'size': 12, 'height': 28, 'color': '{s:_eco_p_2_7|on=#2f9cff,off=outline}', 'enabledWhen': '{state}!=off', 'onClick': 'toggle@{id:_eco_p_2_7}'},
        <String, dynamic>{'type': 'chip', 'label': '{s:_sleep_mode_p_2_11|on=✓ 睡眠,off=睡眠}', 'size': 12, 'height': 28, 'color': '{s:_sleep_mode_p_2_11|on=#2f9cff,off=outline}', 'enabledWhen': '{state}!=off', 'onClick': 'toggle@{id:_sleep_mode_p_2_11}'},
        <String, dynamic>{'type': 'chip', 'label': '{s:_un_straight_blowing_p_2_15|on=✓ 防直吹,off=防直吹}', 'size': 12, 'height': 28, 'color': '{s:_un_straight_blowing_p_2_15|on=#2f9cff,off=outline}', 'enabledWhen': '{state}!=off', 'onClick': 'toggle@{id:_un_straight_blowing_p_2_15}'},
      ],
    },
  ],
};
