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
}
