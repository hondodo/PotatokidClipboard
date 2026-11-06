import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/core/server/account_session.dart';
import 'package:pscreen_home/features/parental/data/parental_admin_api.dart';
import 'package:pscreen_home/features/parental/presentation/parental_page.dart';

/// 家长视图角色行为测试：返回锁定与右上角设置入口的可见性。
class _FakeParentalApi extends ParentalAdminApi {
  const _FakeParentalApi();

  @override
  Future<void> ensureAdminSession({
    required String username,
    required String passwordMd5,
  }) async {}

  @override
  Future<List<ParentalMachine>> fetchMachines() async =>
      const <ParentalMachine>[];

  @override
  Future<List<ParentalMachine>> fetchAvailableMachines() async =>
      const <ParentalMachine>[];

  @override
  Future<List<ParentalSession>> fetchParentalSessions() async =>
      const <ParentalSession>[];
}

Future<void> _pumpPushedParentalPage(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (BuildContext context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ParentalPage(api: _FakeParentalApi()),
                ),
              ),
              child: const Text('打开家长视图'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开家长视图'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => AccountSession.roleNotifier.value = '');

  testWidgets('parent 身份：无返回按钮、拦截系统返回、显示设置入口', (WidgetTester tester) async {
    AccountSession.roleNotifier.value = 'parent';
    await _pumpPushedParentalPage(tester);

    expect(find.byType(ParentalPage), findsOneWidget);
    // 左上角返回按钮被移除。
    expect(find.byType(BackButton), findsNothing);
    // 右上角刷新旁新增设置入口，以及家长专用的扫码设备入口。
    expect(find.byTooltip('设置'), findsOneWidget);
    expect(find.byTooltip('添加/解绑设备'), findsOneWidget);

    // 系统返回（Android 返回键/手势）不能退回进来时的页面。
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(ParentalPage), findsOneWidget);
    // 让「无法返回」提示的 SnackBar 自行消失，避免遗留计时器。
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('user 身份：空态无返回按钮，显示刷新/设置与当前账号角色', (WidgetTester tester) async {
    AccountSession.roleNotifier.value = 'user';
    await _pumpPushedParentalPage(tester);

    expect(find.byType(ParentalPage), findsOneWidget);
    // 空态不再提供返回箭头与「返回中控台」。
    expect(find.byType(BackButton), findsNothing);
    expect(find.text('返回中控台'), findsNothing);
    // 右上角只剩刷新（重新检测权限）与设置。
    expect(find.byTooltip('刷新（重新检测权限）'), findsOneWidget);
    expect(find.byTooltip('设置'), findsOneWidget);
    expect(find.textContaining('当前登录账号：'), findsOneWidget);
    expect(find.text('当前角色：user'), findsOneWidget);
    expect(find.textContaining('只有 user 角色'), findsOneWidget);
  });

  testWidgets('admin 身份：保留返回按钮、无家长设置入口', (WidgetTester tester) async {
    AccountSession.roleNotifier.value = 'admin';
    await _pumpPushedParentalPage(tester);

    expect(find.byType(ParentalPage), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);
    expect(find.byTooltip('设置'), findsNothing);
    expect(find.byTooltip('添加/解绑设备'), findsNothing);

    // admin 仍可通过左上角返回离开家长视图。
    await tester.tap(find.byType(BackButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(ParentalPage), findsNothing);
    expect(find.text('打开家长视图'), findsOneWidget);
  });
}
