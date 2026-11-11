import 'package:flutter/material.dart';
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
    ParentalChild(id: 'c1', name: '弟弟', dailyLimitMin: 1000),
    ParentalChild(id: 'c2', name: '哥哥'),
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

void main() {
  testWidgets('规则页：儿童档案 + 全局设置正常渲染（嵌套 ListView 不崩溃）',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ParentalRulesView(
          config: _config,
          selected: _machine,
          actions: _stubActions(),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('儿童档案'), findsOneWidget);
    expect(find.text('儿童模式总开关'), findsOneWidget);
    expect(find.text('弟弟'), findsWidgets);
    expect(find.text('哥哥'), findsWidgets);
    expect(find.text('全局设置'), findsOneWidget);
    expect(find.text('解锁方式'), findsOneWidget);
  });

  testWidgets('我的页：账号/电视/解锁设置正常渲染（嵌套 ListView 不崩溃）',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ParentalMineView(
          machines: <ParentalMachine>[_machine],
          selected: _machine,
          config: _config,
          myAccount: 'owner1',
          actions: _stubActions(),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('账号与权限'), findsOneWidget);
    expect(find.text('我的电视'), findsOneWidget);
    expect(find.text('家长账号（ownerAccount）'), findsOneWidget);
    expect(find.text('保存设置'), findsOneWidget);
  });
}
