import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/features/parental/presentation/parental_mine_cards.dart';

/// 「我的」页合并后各卡片的行为测试（原设置弹窗测试已随弹窗删除）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('账号卡：家长号与实时通道号两行分开、可进设置', (WidgetTester tester) async {
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

    // 两层身份彻底分开：家长号（可改）+ 本机实时通道号（只读）。
    expect(find.text('家长号（跨设备身份）'), findsOneWidget);
    expect(find.text('mama_01'), findsOneWidget);
    expect(find.text('本机实时通道号（设备身份 · 只读）'), findsOneWidget);
    expect(find.text('parent.phone.8f3c21'), findsOneWidget);
    expect(find.textContaining('永不改名、不禁用'), findsOneWidget);
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
    // 通道号未注入时显示检测中。
    expect(find.text('检测中…'), findsOneWidget);
  });

  testWidgets('账号卡：未设独立家长号时，第一行不与通道号重复显示派生值',
      (WidgetTester tester) async {
    // 回归真机发现：页面壳的登录账号在未 claim 时会回落到派生号，
    // 若直接当家长号展示，会和第二行通道号一模一样。页面壳传空值后，
    // 卡片应显示「未设置（使用设备号）」，只有第二行展示派生号。
    const String derived = 'parent.parent.637143eef8c2333f';
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: ParentalAccountCard(account: '', channelAccount: derived),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('未设置（使用设备号）'), findsOneWidget);
    expect(find.text(derived), findsOneWidget); // 派生号只出现在通道号一行
    expect(find.text('家长号（跨设备身份）'), findsOneWidget);
    expect(find.text('本机实时通道号（设备身份 · 只读）'), findsOneWidget);
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
