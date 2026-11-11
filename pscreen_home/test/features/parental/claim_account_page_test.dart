import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/features/parental/presentation/claim_account_page.dart';

/// 路由表不分 flavor，页面必须自己挡住中控端深链。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('非 parent flavor 只显示「仅家长端可用」提示', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: ClaimAccountPage()));
    await tester.pumpAndSettle();

    expect(find.text('此页面仅家长端可用'), findsOneWidget);
    expect(find.byType(TextField), findsNothing,
        reason: '中控端不应看到改名表单');
    expect(find.text('设置登录名'), findsOneWidget, reason: 'AppBar 标题');
  });
}
