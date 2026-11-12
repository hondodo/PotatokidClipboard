import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/features/parental/presentation/parental_mine_cards.dart';

/// 「我的」页合并后各卡片的行为测试（原设置弹窗测试已随弹窗删除）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('账号卡：只展示家长号，技术通道号收进说明页、可进设置',
      (WidgetTester tester) async {
    int tapped = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ParentalAccountCard(
          account: 'mama_01',
          channelAccount: 'parent.phone.8f3c21',
          onEdit: () => tapped++,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // 「我的」页只留家长看得懂的身份；设备派生号在「家长号与跨设备」页展开。
    expect(find.text('家长号（跨设备身份）'), findsOneWidget);
    expect(find.text('mama_01'), findsOneWidget);
    expect(find.text('本机实时通道号（设备身份 · 只读）'), findsNothing);
    expect(find.text('parent.phone.8f3c21'), findsNothing);
    expect(find.text('家长号怎么跨设备 ›'), findsOneWidget);
    await tester.tap(find.byTooltip('设置家长号'));
    await tester.pumpAndSettle();
    expect(tapped, 1);
  });

  testWidgets('账号卡：家长号未设置时提示回落设备号', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: ParentalAccountCard(account: '')),
    ));
    await tester.pumpAndSettle();
    expect(find.text('未设置（使用设备号）'), findsOneWidget);
    // 「我的」页不再露出派生号（避免一眼看到两串看不懂的编号）。
    expect(find.text('检测中…'), findsNothing);
  });

  testWidgets('账号卡：未设独立家长号时显示回落说明，不暴露派生号',
      (WidgetTester tester) async {
    // 回归真机发现：页面壳的登录账号在未 claim 时会回落到派生号。
    // 页面壳传空值后卡片显示「未设置（使用设备号）」，派生号不在本页露出。
    const String derived = 'parent.parent.637143eef8c2333f';
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: ParentalAccountCard(account: '', channelAccount: derived),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('未设置（使用设备号）'), findsOneWidget);
    expect(find.text(derived), findsNothing);
    expect(find.text('家长号（跨设备身份）'), findsOneWidget);
    expect(find.text('本机实时通道号（设备身份 · 只读）'), findsNothing);
  });

  testWidgets('家长端名称卡：用人话说明、可回显、不出现 ownerAccount',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: ParentalDisplayNameCard(initialName: '小米10s家长端')),
    ));
    await tester.pumpAndSettle();

    expect(find.text('我在电视上的名字'), findsOneWidget);
    expect(find.textContaining('电视和解锁请求里会显示这个名字'), findsOneWidget);
    // 明确区分三种改名，避免用户混淆。
    expect(find.textContaining('这不是电视的备注名'), findsOneWidget);
    expect(find.text('保存名字'), findsOneWidget);
    final TextField field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, '小米10s家长端');
    // 看不懂的技术字段不出现。
    expect(find.textContaining('ownerAccount'), findsNothing);
    expect(find.textContaining('投递目标'), findsNothing);
  });

  testWidgets('连接与更新卡：未接入通道时降级显示、含版本与检查更新',
      (WidgetTester tester) async {
    // 不注册全局 RealtimeChannel / AppVersion，验证卡片优雅降级不抛异常。
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: ParentalConnectionCard()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('连接与更新'), findsOneWidget);
    expect(find.text('遥控通道：未接入'), findsOneWidget);
    expect(find.textContaining('检查更新'), findsOneWidget);
    // 中控台专属设置不泄漏到家长端。
    expect(find.text('屏保时间'), findsNothing);
    expect(find.text('界面缩放'), findsNothing);
  });
}
