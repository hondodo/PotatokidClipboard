import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_screen/app/config/app_config.dart';
import 'package:pscreen_screen/core/utils/app_settings.dart';
import 'package:pscreen_screen/core/utils/device_credentials.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// claim 闸门回归：中控端 / TV 端不开启闸门时，账号必须仍是派生值。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const String deviceId = 'abcdef0123456789';
  const String derived = 'parent.parent.$deviceId';
  const String defaultMd5 = 'e10adc3949ba59abbe56e057f20f883e';

  setUp(() async {
    await AppSettings.instance.clearAllPersisted();
    SharedPreferences.setMockInitialValues(<String, Object>{
      'app_device_id_fallback_v1': deviceId,
    });
    AppConfig.enableChangeAccount = false;
    DeviceCredentials.configureAccountScope('parent.parent');
    DeviceCredentials.configureClaimEnabled(false);
  });

  tearDown(() async {
    DeviceCredentials.configureClaimEnabled(false);
    AppConfig.enableChangeAccount = false;
    await AppSettings.instance.clearAllPersisted();
  });

  test('闸门关闭：账号恒为派生值，即使本地已有 claimedAccount', () async {
    expect(await DeviceCredentials.account(), derived);
    await AppSettings.instance.setClaimedAccount('mama_01');
    expect(await DeviceCredentials.account(), derived,
        reason: '中控端 / TV 端不读 claimedAccount，登录链路不变');
    expect(await DeviceCredentials.enforceDerivedAccount(), derived);
    expect(AppSettings.instance.remoteAccount, derived);
  });

  test('闸门开启但未 claim：仍走设备派生自举', () async {
    DeviceCredentials.configureClaimEnabled(true);
    expect(await DeviceCredentials.account(), derived);
    expect(await DeviceCredentials.enforceDerivedAccount(), derived);
  });

  test('闸门开启且已 claim：重启校正不再把账号抹回派生值', () async {
    await AppSettings.instance.setClaimedAccount('mama_01');
    DeviceCredentials.configureClaimEnabled(true);
    expect(await DeviceCredentials.enforceDerivedAccount(), 'mama_01');
    expect(await DeviceCredentials.account(), 'mama_01');
    expect(AppSettings.instance.remoteAccount, 'mama_01');
    expect(AppSettings.instance.claimedAccount, 'mama_01');
  });

  test('闸门关闭时口令恒为默认值；开启后才使用 claim 新口令', () async {
    expect(DeviceCredentials.passwordMd5(), defaultMd5);
    await AppSettings.instance.setClaimedAccount('mama_01');
    await AppSettings.instance.setClaimedPassword('random-token');
    expect(DeviceCredentials.password(), DeviceCredentials.defaultPassword,
        reason: '中控端 / TV 端不得感知 claim 凭据');
    expect(DeviceCredentials.passwordMd5(), defaultMd5);

    DeviceCredentials.configureClaimEnabled(true);
    expect(DeviceCredentials.password(), 'random-token');
    expect(DeviceCredentials.passwordMd5(), isNot(defaultMd5),
        reason: '自定义登录名不能沿用可猜的默认口令');
  });

  test('重置会清除全部 claim 凭据与展示名', () async {
    await AppSettings.instance.setClaimedAccount('mama_01');
    await AppSettings.instance.setClaimedPassword('random-token');
    await AppSettings.instance.setDisplayName('妈妈');
    expect(AppSettings.instance.claimedAccount, 'mama_01');
    expect(AppSettings.instance.claimedPassword, 'random-token');
    expect(AppSettings.instance.displayName, '妈妈');
    await AppSettings.instance.clearAllPersisted();
    expect(AppSettings.instance.claimedAccount, isEmpty);
    expect(AppSettings.instance.claimedPassword, isEmpty);
    expect(AppSettings.instance.displayName, isEmpty);
  });

  test('claim 凭据写入独立持久化键', () async {
    await AppSettings.instance.setClaimedAccount('  mama_01  ');
    await AppSettings.instance.setClaimedPassword('  random-token  ');
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('app_claimed_account_v1'), 'mama_01');
    expect(prefs.getString('app_claimed_password_v1'), 'random-token');
    expect(prefs.getString('app_remote_account_v1'), isNull,
        reason: '不得复用调试账号键');
    expect(prefs.getString('app_remote_password_v1'), isNull,
        reason: '不得复用调试口令键');
  });
}
