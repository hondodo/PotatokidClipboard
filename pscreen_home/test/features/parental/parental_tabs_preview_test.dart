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
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
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
}
