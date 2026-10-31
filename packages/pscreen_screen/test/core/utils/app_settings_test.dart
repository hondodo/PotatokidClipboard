import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_screen/core/utils/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('remoteAccount 默认空串，setRemoteAccount 内存与持久化同步更新', () async {
    final AppSettings settings = AppSettings.instance;
    await settings.clearAllPersisted();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await settings.ensureLoaded();
    expect(settings.remoteAccount, isEmpty);

    await settings.setRemoteAccount('ABCD');
    expect(settings.remoteAccount, 'ABCD');
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('app_remote_account_v1'), 'ABCD');
  });

  test('clearAllPersisted 复位 remoteAccount', () async {
    final AppSettings settings = AppSettings.instance;
    await settings.clearAllPersisted();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await settings.ensureLoaded();
    await settings.setRemoteAccount('EFGH');

    await settings.clearAllPersisted();
    expect(settings.remoteAccount, isEmpty);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('app_remote_account_v1'), isNull);
  });
}
