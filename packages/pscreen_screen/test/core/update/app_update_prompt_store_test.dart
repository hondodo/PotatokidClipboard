import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_screen/core/update/app_update_prompt_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('同一版本只提示一次，且重启后仍记得', () async {
    const String appId = 'case-restart';
    final AppUpdatePromptStore store = await AppUpdatePromptStore.open();
    expect(store.isPrompted(appId, 'rel_1'), isFalse);

    await store.markPrompted(appId, 'rel_1');
    expect(store.isPrompted(appId, 'rel_1'), isTrue);

    // 模拟重启：重新打开一份 store，记录仍持久化。
    final AppUpdatePromptStore reopened = await AppUpdatePromptStore.open();
    expect(reopened.isPrompted(appId, 'rel_1'), isTrue);
  });

  test('出现新版本（新 releaseId）会再提示一次', () async {
    const String appId = 'case-new-version';
    final AppUpdatePromptStore store = await AppUpdatePromptStore.open();
    await store.markPrompted(appId, 'rel_1');

    expect(store.isPrompted(appId, 'rel_2'), isFalse);
    await store.markPrompted(appId, 'rel_2');
    expect(store.isPrompted(appId, 'rel_2'), isTrue);
    // 旧版本记录仍在（避免 A→B→A 来回时重复提示）。
    expect(store.isPrompted(appId, 'rel_1'), isTrue);
  });

  test('不同 appId 的记录互不干扰', () async {
    final AppUpdatePromptStore store = await AppUpdatePromptStore.open();
    await store.markPrompted('app-one', 'rel_same');

    expect(store.isPrompted('app-one', 'rel_same'), isTrue);
    expect(store.isPrompted('app-two', 'rel_same'), isFalse);
  });

  test('空 versionKey 不记录也不误判', () async {
    const String appId = 'case-empty';
    final AppUpdatePromptStore store = await AppUpdatePromptStore.open();
    await store.markPrompted(appId, '');
    expect(store.isPrompted(appId, ''), isFalse);
  });

  test('重复标记幂等', () async {
    const String appId = 'case-idempotent';
    final AppUpdatePromptStore store = await AppUpdatePromptStore.open();
    await store.markPrompted(appId, 'rel_1');
    await store.markPrompted(appId, 'rel_1');

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getStringList('${AppUpdatePromptStore.keyPrefix}$appId'),
      <String>['rel_1'],
    );
  });

  test('超过上限只保留最近 20 个版本', () async {
    const String appId = 'case-trim';
    final AppUpdatePromptStore store = await AppUpdatePromptStore.open();
    for (int i = 0; i < 25; i++) {
      await store.markPrompted(appId, 'rel_$i');
    }

    expect(store.isPrompted(appId, 'rel_0'), isFalse); // 最旧的被裁掉
    expect(store.isPrompted(appId, 'rel_4'), isFalse);
    expect(store.isPrompted(appId, 'rel_5'), isTrue);
    expect(store.isPrompted(appId, 'rel_24'), isTrue);

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getStringList('${AppUpdatePromptStore.keyPrefix}$appId')?.length,
      20,
    );
  });

  test('keyPrefix 与「重置」白名单约定保持一致', () {
    // AppSettings.clearAllPersisted() 依据该前缀跳过清理，改动需两处同步。
    expect(AppUpdatePromptStore.keyPrefix, 'app_update_prompted_v1_');
  });
}
