import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_screen/core/utils/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('nimAccount 默认空串，setNimAccount 内存与持久化同步更新', () async {
    final AppSettings settings = AppSettings.instance;
    await settings.clearAllPersisted();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await settings.ensureLoaded();
    expect(settings.nimAccount, isEmpty);

    await settings.setNimAccount('ABCD');
    expect(settings.nimAccount, 'ABCD');
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('app_nim_account_v1'), 'ABCD');
  });

  test('clearAllPersisted 复位 nimAccount', () async {
    final AppSettings settings = AppSettings.instance;
    await settings.clearAllPersisted();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await settings.ensureLoaded();
    await settings.setNimAccount('EFGH');

    await settings.clearAllPersisted();
    expect(settings.nimAccount, isEmpty);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('app_nim_account_v1'), isNull);
  });

  test('wpPassword 默认空串，setWpPassword 内存与持久化同步更新', () async {
    final AppSettings settings = AppSettings.instance;
    await settings.clearAllPersisted();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await settings.ensureLoaded();
    expect(settings.wpPassword, isEmpty);

    await settings.setWpPassword('12345678');
    expect(settings.wpPassword, '12345678');
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('app_wp_password_v1'), '12345678');
  });

  test('clearAllPersisted 复位 wpPassword', () async {
    final AppSettings settings = AppSettings.instance;
    await settings.clearAllPersisted();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await settings.ensureLoaded();
    await settings.setWpPassword('abcd');

    await settings.clearAllPersisted();
    expect(settings.wpPassword, isEmpty);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('app_wp_password_v1'), isNull);
  });
}
