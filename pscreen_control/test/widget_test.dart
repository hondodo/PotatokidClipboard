import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pscreen_control/app/storage/app_settings.dart';
import 'package:pscreen_control/features/settings/presentation/settings_page.dart';
import 'package:pscreen_control/main.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.ensureLoaded();
  });

  testWidgets('App renders settings home when not logged in',
      (WidgetTester tester) async {
    await tester.pumpWidget(const PscreenControlApp(home: SettingsPage()));
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('登录'), findsOneWidget);
  });
}
