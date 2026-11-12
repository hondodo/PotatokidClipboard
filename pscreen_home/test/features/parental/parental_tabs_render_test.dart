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
      selectDevice: (_) {},
      renameMachine: (_) {},
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

  testWidgets('我的页：无孩子档案时，已绑定电视的遥控按钮仍常驻可点',
      (WidgetTester tester) async {
    // 回归真机反馈：未添加孩子档案时也必须能直接遥控设备。
    // 遥控是设备级操作，不能挂在孩子卡上，也不能被空 children 挡住。
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    int pushed = 0;
    final ParentalActions actions = ParentalActions(
      reload: () async {},
      saveConfig: (_) async {},
      unlock: (_) async {},
      openDeviceManager: () async {},
      push: (_) async => pushed++,
      sendRemoteCommand: (_) async {},
      refreshPermission: () async {},
      toggleChildLock: (_) {},
      addChildExtra: (_) {},
      editChild: (_) {},
      unbind: (_) {},
      selectDevice: (_) {},
      renameMachine: (_) {},
    );
    // children 为空 = 没有任何孩子档案。
    final ParentalConfig noChildren = ParentalConfig(
      mode: 'on',
      children: const <ParentalChild>[],
      unlockMode: 'remote',
      ownerAccount: 'owner1',
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ParentalMineView(
          machines: <ParentalMachine>[_machine],
          selected: _machine,
          config: noChildren,
          myAccount: 'owner1',
          actions: actions,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // 已绑定电视仍显示，且每台电视行都有常驻遥控入口。
    expect(find.text('红米笔记本'), findsOneWidget);
    expect(find.byTooltip('遥控 红米笔记本'), findsOneWidget);
    // 点遥控能进入遥控页（设备级能力，与有无档案无关）。
    await tester.tap(find.byTooltip('遥控 红米笔记本'));
    await tester.pumpAndSettle();
    expect(pushed, 1);
  });

  testWidgets('我的页：账号/电视/解锁设置正常渲染（嵌套 ListView 不崩溃）',
      (WidgetTester tester) async {
    // 五组内容较长，放大视口确保底部「连接与更新」卡也进入构建范围。
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
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

    // 五组结构：账号（家长号+通道号两行）/ 我在电视上的名字 / 我的电视 / 解锁方式 / 连接与更新。
    expect(find.text('家长号（跨设备身份）'), findsOneWidget);
    expect(find.text('本机实时通道号（设备身份 · 只读）'), findsOneWidget);
    expect(find.text('我在电视上的名字'), findsOneWidget);
    expect(find.text('我的电视'), findsOneWidget);
    expect(find.text('解锁方式'), findsOneWidget);
    expect(find.text('连接与更新'), findsOneWidget);
    expect(find.text('保存名字'), findsOneWidget);
    expect(find.text('保存设置'), findsOneWidget);
    // 旧的技术字段/大块不再出现。
    expect(find.text('账号与权限'), findsNothing);
    expect(find.textContaining('ownerAccount'), findsNothing);
    expect(find.textContaining('投递目标'), findsNothing);
    expect(find.text('重新检查权限'), findsNothing);
  });
}
