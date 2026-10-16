import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pscreen_control/app/storage/app_settings.dart';
import 'package:pscreen_control/main.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.ensureLoaded();
  });

  testWidgets('App renders placeholder home', (WidgetTester tester) async {
    await tester.pumpWidget(const PscreenControlApp());
    expect(find.text('PScreen Control'), findsOneWidget);
  });
}
