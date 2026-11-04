import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/features/parental/data/parental_admin_api.dart';
import 'package:pscreen_home/features/parental/presentation/parental_device_manager_sheet.dart';

ParentalMachine _machine(String id, String name) => ParentalMachine(
  id: id,
  name: name,
  kind: 'tv',
  owner: 'home',
  parents: const <String>['home'],
  commAccount: 'tv-$id',
  online: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('解绑后设备保留在「可绑定设备」，可重新绑定', (WidgetTester tester) async {
    final List<String> unbound = <String>[];
    final ParentalMachine machine = _machine('mA', '客厅电视');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ParentalDeviceManagerSheet(
            bound: <ParentalMachine>[machine],
            available: const <ParentalMachine>[],
            onBind: (String id) async => null,
            onUnbind: (String id) async {
              unbound.add(id);
              return null;
            },
            onScanBind: (String account) async => null,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('已绑定设备'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '解绑'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '解绑'));
    await tester.pumpAndSettle();

    expect(unbound, <String>['mA']);
    expect(find.text('已绑定设备'), findsNothing);
    expect(find.text('可绑定设备'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '绑定'), findsOneWidget);
    expect(find.textContaining('设备记录仍保留'), findsWidgets);
  });

  testWidgets('可绑定设备可绑定并移动到已绑定列表', (WidgetTester tester) async {
    final List<String> bound = <String>[];
    final ParentalMachine machine = _machine('mB', '卧室电视');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ParentalDeviceManagerSheet(
            bound: const <ParentalMachine>[],
            available: <ParentalMachine>[machine],
            onBind: (String id) async {
              bound.add(id);
              return null;
            },
            onUnbind: (String id) async => null,
            onScanBind: (String account) async => null,
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.widgetWithText(TextButton, '绑定'));
    await tester.pumpAndSettle();

    expect(bound, <String>['mB']);
    expect(find.text('已绑定设备'), findsOneWidget);
    expect(find.text('可绑定设备'), findsNothing);
  });
}
