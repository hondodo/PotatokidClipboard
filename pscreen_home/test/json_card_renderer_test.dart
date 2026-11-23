import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pscreen_home/app/config/ha_config.dart';
import 'package:pscreen_home/features/home/domain/models/card_layout.dart';
import 'package:pscreen_home/features/home/domain/models/device_type_dictionary.dart';
import 'package:pscreen_home/features/home/domain/models/ha_device_group.dart';
import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';
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
      label: '开关状态', mainFmt: '{v}', subTpl: '{state}',
      icon: '⏻', color: '#4dd4ac',
      buttons: <DeviceCardButton>[DeviceCardButton(label: '开关', action: 'toggle')],
    );
    await tester.pumpWidget(MaterialApp(
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
    ));
    await tester.pumpAndSettle();
    // 渲染成功 = 没抛异常；验证标题出现。
    expect(find.textContaining('客厅插座'), findsWidgets);
  });

  testWidgets('JsonCardRenderer 渲染 multi_switch 每路大按钮不抛异常', (WidgetTester tester) async {
    final HaDeviceGroup group = HaDeviceGroup(
      deviceId: 'dev_sw',
      title: '小米双开',
      entities: <HaEntityStateModel>[
        _entity('switch.a_on_p_2_1', 'on', name: '左键'),
        _entity('switch.a_on_p_3_1', 'off', name: '右键'),
      ],
    );
    const DeviceCardConfig card = DeviceCardConfig(
      label: '已开启路数', mainFmt: '{v}', subTpl: '{state}',
      icon: '▦', color: '#a3a3a3',
    );
    await tester.pumpWidget(MaterialApp(
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
    ));
    await tester.pumpAndSettle();
    // 每路一个大按钮：label 显示的应该是实体名（左键/右键），不是"已开启路数 2/4"。
    expect(find.textContaining('左键'), findsWidgets);
    expect(find.textContaining('右键'), findsWidgets);
  });

  testWidgets('JsonCardRenderer 渲染服务端自定义 layout(含sparkline)不抛异常', (WidgetTester tester) async {
    final HaDeviceGroup group = HaDeviceGroup(
      deviceId: 'dev_socket',
      title: '客厅插座',
      entities: <HaEntityStateModel>[_entity('switch.socket_on', 'on', name: '插座')],
    );
    final CardLayoutNode layout = CardLayoutNode.fromJson(<String, dynamic>{
      'type': 'column',
      'gap': 8,
      'children': <dynamic>[
        <String, dynamic>{'type': 'text', 'value': '{title}', 'size': 14},
        <String, dynamic>{'type': 'text', 'value': '{main}', 'size': 24, 'color': '{color}'},
        <String, dynamic>{
          'type': 'sparkline', 'metric': 'power', 'height': 60, 'showLabels': true,
        },
      ],
    });
    final DeviceCardConfig card = DeviceCardConfig(
      label: '功率', mainFmt: '{v}W', subTpl: '{state}', color: '#4dd4ac', layout: layout,
    );
    await tester.pumpWidget(MaterialApp(
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
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('客厅插座'), findsWidgets);
  });

  testWidgets('JsonCardRenderer 渲染 row 内未标记 expand 的 column 不抛无限宽度异常',
      (WidgetTester tester) async {
    final HaDeviceGroup group = HaDeviceGroup(
      deviceId: 'dev_light',
      title: '客厅 大灯',
      entities: <HaEntityStateModel>[_entity('light.living', 'off', name: '大灯')],
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
                  'type': 'text', 'value': '{title}', 'size': 14,
                  'weight': 600, 'maxLines': 1,
                },
                <String, dynamic>{'type': 'divider', 'thickness': 2, 'gap': 2},
                <String, dynamic>{
                  'type': 'text', 'value': '{sub}', 'size': 12,
                  'color': '{color}', 'maxLines': 1,
                },
              ],
            },
          ],
        },
      ],
    });
    final DeviceCardConfig card = DeviceCardConfig(
      label: '开关状态', mainFmt: '{v}', subTpl: '{state}',
      icon: '✦', color: '#4dd4ac', layout: layout,
    );
    await tester.pumpWidget(MaterialApp(
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
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('客厅 大灯'), findsWidgets);
  });

  test('CardEvalContext.parseValueMap 解析 ESP 风格替换表', () {
    final Map<String, String>? map = CardEvalContext.parseValueMap(
        'on=着灯,off=关闭；open=开，close=关\nanother=\'带引号值\'');
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

  testWidgets('JsonCardRenderer 圆形按钮 + 可交互亮度条渲染并派发亮度动作', (WidgetTester tester) async {
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
      label: '灯光状态', mainFmt: '{v}', subTpl: '{state}',
      icon: '✦', color: '#ff6a3a', layout: layout,
    );
    final List<String> actions = <String>[];
    await tester.pumpWidget(MaterialApp(
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
    ));
    await tester.pumpAndSettle();
    // 值替换生效：on -> 着灯。
    expect(find.textContaining('着灯 · 亮度25%'), findsOneWidget);
    // 圆形电源键点击派发 toggle@。
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(actions, contains('toggle@light.living'));

    // 点亮度条中部：GradientSlider 松手派发 brightness@实体:百分比。
    final GradientSlider slider = tester.widget<GradientSlider>(
        find.byType(GradientSlider));
    slider.onChangeEnd?.call(60);
    expect(actions.any((String a) => a.startsWith('brightness@light.living:')), isTrue);
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
      label: '灯光状态', mainFmt: '{v}', subTpl: '{state}',
      icon: '☀', color: '#facc15', layout: layout,
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 320,
          height: 120,
          child: JsonCardRenderer(
            group: group, card: card, typeKey: 'light',
            onOpenDetail: () {}, onAction: (_) {},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    // 无论在线离线，GradientSlider 都必须渲染出来（常显）
    expect(find.byType(GradientSlider), findsOneWidget);
    final GradientSlider slider = tester.widget<GradientSlider>(find.byType(GradientSlider));
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
      label: '灯光状态', mainFmt: '{v}', subTpl: '{state}',
      icon: '☀', color: '#facc15', layout: layout,
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 320,
          height: 120,
          child: JsonCardRenderer(
            group: group, card: card, typeKey: 'light',
            onOpenDetail: () {}, onAction: (_) {},
          ),
        ),
      ),
    ));
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
}
