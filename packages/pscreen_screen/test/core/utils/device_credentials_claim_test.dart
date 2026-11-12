import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_screen/app/config/app_config.dart';
import 'package:pscreen_screen/core/utils/app_settings.dart';
import 'package:pscreen_screen/core/utils/device_credentials.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 双凭据回归：
/// - 实时通道凭据（channelAccount/channelPassword）恒为设备派生号 + 默认口令，
///   任何 flavor、是否 claim 都不改变它——派生号永不改名、永不禁用；
/// - 管理登录凭据（account/password）仅 parent flavor 开启闸门后才优先用家长号；
///   中控端 / TV 端不开启闸门时，管理登录也恒为派生值，链路不变。
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

  test('实时通道账号恒为派生号，任何 flavor / claim 状态都不改变', () async {
    expect(await DeviceCredentials.channelAccount(), derived);
    await AppSettings.instance.setClaimedAccount('mama_01');
    await AppSettings.instance.setClaimedPassword('self-chosen-password');
    DeviceCredentials.configureClaimEnabled(true);
    expect(await DeviceCredentials.channelAccount(), derived,
        reason: '设置家长号后实时通道仍必须用派生号，不得被切成家长号');
  });

  test('实时通道口令恒为默认 123456，与家长号口令解耦', () async {
    expect(DeviceCredentials.channelPasswordMd5(), defaultMd5);
    await AppSettings.instance.setClaimedAccount('mama_01');
    await AppSettings.instance.setClaimedPassword('self-chosen-password');
    DeviceCredentials.configureClaimEnabled(true);
    expect(DeviceCredentials.channelPassword(), DeviceCredentials.defaultPassword);
    expect(DeviceCredentials.channelPasswordMd5(), defaultMd5,
        reason: '派生号账号永不禁用，实时通道始终用默认口令可登录');
  });

  test('闸门关闭：管理登录恒为派生值，即使本地已有家长号', () async {
    expect(await DeviceCredentials.account(), derived);
    await AppSettings.instance.setClaimedAccount('mama_01');
    expect(await DeviceCredentials.account(), derived,
        reason: '中控端 / TV 端不读家长号，登录链路不变');
    expect(await DeviceCredentials.enforceDerivedAccount(), derived);
    expect(AppSettings.instance.remoteAccount, derived);
  });

  test('闸门开启但未设置家长号：管理登录仍走设备派生自举', () async {
    DeviceCredentials.configureClaimEnabled(true);
    expect(await DeviceCredentials.account(), derived);
    expect(await DeviceCredentials.enforceDerivedAccount(), derived);
  });

  test('闸门开启且已设置家长号：管理登录用家长号，通道仍用派生号', () async {
    await AppSettings.instance.setClaimedAccount('mama_01');
    DeviceCredentials.configureClaimEnabled(true);
    expect(await DeviceCredentials.account(), 'mama_01');
    expect(await DeviceCredentials.channelAccount(), derived,
        reason: '两套凭据彻底分开，改家长号不影响实时通道');
  });

  test('管理口令：闸门关闭恒默认；开启后家长号可自设口令', () async {
    expect(DeviceCredentials.passwordMd5(), defaultMd5);
    await AppSettings.instance.setClaimedAccount('mama_01');
    await AppSettings.instance.setClaimedPassword('self-chosen-password');
    expect(DeviceCredentials.password(), DeviceCredentials.defaultPassword,
        reason: '中控端 / TV 端不得感知家长号口令');
    expect(DeviceCredentials.passwordMd5(), defaultMd5);

    DeviceCredentials.configureClaimEnabled(true);
    expect(DeviceCredentials.password(), 'self-chosen-password');
    expect(DeviceCredentials.passwordMd5(), isNot(defaultMd5),
        reason: '家长号口令可自设，换设备凭号+口令登录');
    // 关键：管理口令变了，通道口令仍是默认。
    expect(DeviceCredentials.channelPasswordMd5(), defaultMd5);
  });

  test('重置会清除全部家长号凭据，但派生号仍可自举登录', () async {
    await AppSettings.instance.setClaimedAccount('mama_01');
    await AppSettings.instance.setClaimedPassword('self-chosen-password');
    await AppSettings.instance.setDisplayName('妈妈');
    expect(AppSettings.instance.claimedAccount, 'mama_01');
    await AppSettings.instance.clearAllPersisted();
    expect(AppSettings.instance.claimedAccount, isEmpty);
    expect(AppSettings.instance.claimedPassword, isEmpty);
    expect(AppSettings.instance.displayName, isEmpty);
    // 重置后管理登录回落到派生号 + 默认口令，不再锁死。
    DeviceCredentials.configureClaimEnabled(true);
    expect(await DeviceCredentials.account(), derived);
    expect(DeviceCredentials.passwordMd5(), defaultMd5);
    expect(await DeviceCredentials.channelAccount(), derived);
  });

  test('家长号凭据写入独立持久化键', () async {
    await AppSettings.instance.setClaimedAccount('  mama_01  ');
    await AppSettings.instance.setClaimedPassword('  self-chosen-password  ');
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('app_claimed_account_v1'), 'mama_01');
    expect(prefs.getString('app_claimed_password_v1'), 'self-chosen-password');
    expect(prefs.getString('app_remote_account_v1'), isNull,
        reason: '家长号不得复用调试账号键');
    expect(prefs.getString('app_remote_password_v1'), isNull,
        reason: '家长号不得复用调试口令键');
  });
}
