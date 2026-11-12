import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/features/parental/data/parental_admin_api.dart';
import 'package:pscreen_home/features/parental/domain/parental_config.dart';
import 'package:pscreen_home/features/parental/presentation/parental_common.dart';
import 'package:pscreen_home/features/parental/presentation/parental_mine_tab.dart';
import 'package:pscreen_home/features/parental/presentation/parental_rules_tab.dart';
import 'package:pscreen_home/features/parental/presentation/parental_today_page.dart';
import 'package:pscreen_screen/core/network/realtime_channel.dart';

ParentalActions _stubActions() => ParentalActions(
      reload: () async {},
      saveConfig: (_) async {},
      unlock: (_) async {},
      openDeviceManager: () async {},
      push: (_) async {},
      sendRemoteCommand: (_) async {},
      refreshPermission: () async {},
      toggleChildLock: (_) {},
      addChildExtra: (_) {},
      editChild: (_) {},
      unbind: (_) {},
      selectDevice: (_) {},
      renameMachine: (_) {},
    );

final ParentalConfig _config = ParentalConfig(
  mode: 'on',
  children: <ParentalChild>[
    ParentalChild(id: 'c1', name: '弟弟', age: 7, dailyLimitMin: 1000),
    ParentalChild(id: 'c2', name: '哥哥', age: 11),
  ],
  unlockMode: 'remote',
  ownerAccount: 'owner1',
);

final ParentalMachine _machine = ParentalMachine(
  id: 'm1',
  name: '红米笔记本',
  nameSet: true,
  kind: 'tv',
  owner: 'owner1',
  parents: const <String>['owner1'],
  commAccount: 'mi10s',
  online: true,
);

Future<void> _renderToFile(WidgetTester tester, Widget widget, String path) async {
  await tester.pumpWidget(
    MaterialApp(
      // 与 parent flavor 真机一致：浅底 #F7F9F8 + 深绿主色 #0F6E56。
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F6E56)),
        scaffoldBackgroundColor: const Color(0xFFF7F9F8),
        cardTheme: CardThemeData(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: Color(0xFFE6ECE9)),
          ),
        ),
      ),
      home: Scaffold(body: RepaintBoundary(key: const Key('capture'), child: widget)),
    ),
  );
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    final RenderRepaintBoundary boundary = tester.firstRenderObject<RenderRepaintBoundary>(
      find.byKey(const Key('capture')),
    );
    final ui.Image image = await boundary.toImage(pixelRatio: 2);
    final ByteData? bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(path).writeAsBytes(bytes!.buffer.asUint8List());
  });
}

void main() {
  testWidgets('渲染 规则页 到 PNG', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(840, 2800);
    tester.view.devicePixelRatio = 2;
    await _renderToFile(
      tester,
      ParentalRulesView(config: _config, selected: _machine, actions: _stubActions()),
      r'E:\Code\potatokid_clipboard\.workbuddy\screenshots\rules_preview.png',
    );
  });

  testWidgets('渲染 我的页 到 PNG', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(840, 2800);
    tester.view.devicePixelRatio = 2;
    await _renderToFile(
      tester,
      ParentalMineView(
        machines: <ParentalMachine>[_machine],
        selected: _machine,
        config: _config,
        myAccount: 'owner1',
        actions: _stubActions(),
      ),
      r'E:\Code\potatokid_clipboard\.workbuddy\screenshots\mine_preview.png',
    );
  });

  testWidgets('渲染 今天页 到 PNG', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(840, 2800);
    tester.view.devicePixelRatio = 2;
    final String today = <String>[
      DateTime.now().year.toString().padLeft(4, '0'),
      DateTime.now().month.toString().padLeft(2, '0'),
      DateTime.now().day.toString().padLeft(2, '0'),
    ].join('-');
    final List<RealtimeEvent> watch = <RealtimeEvent>[
      RealtimeEvent(
        id: 'w1',
        from: 'mi10s',
        to: '',
        event: 'parental_watch',
        data: <String, dynamic>{
          'date': today,
          'childIds': <String>['c1'],
          'dailySecByChild': <String, dynamic>{'c1': 3120},
        },
        ts: DateTime.now().millisecondsSinceEpoch,
      ),
    ];
    await _renderToFile(
      tester,
      ParentalTodayView(
        machines: <ParentalMachine>[_machine],
        selected: _machine,
        config: _config,
        watchEvents: watch,
        activeEvents: const <RealtimeEvent>[],
        unlockEvents: const <RealtimeEvent>[],
        unlockAckEvents: const <RealtimeEvent>[],
        sessions: const <ParentalSession>[],
        myAccount: 'owner1',
        isAdmin: false,
        actions: _stubActions(),
      ),
      r'E:\Code\potatokid_clipboard\.workbuddy\screenshots\today_preview.png',
    );
  });
}
