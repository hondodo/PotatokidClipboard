import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:pscreen_screen/core/di/screen_modules.dart';
import 'package:pscreen_screen/core/logging/log_service.dart';
import 'package:pscreen_screen/features/msg/application/current_scene_provider.dart';

class _FakeSceneProvider extends CurrentSceneProvider {
  const _FakeSceneProvider();

  @override
  String describe() => '测试场景';
}

void main() {
  // 必须初始化绑定：MsgModule 注册时会给 nim_core_v2 的 MethodChannel 挂 handler，
  // 没有 binary messenger 会直接断言失败（Cannot set the method call handler
  // before the binary messenger has been initialized）。
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await GetIt.instance.reset();
    GetIt.instance.registerLazySingleton<CurrentSceneProvider>(
      () => const _FakeSceneProvider(),
    );
  });

  tearDown(() async {
    await GetIt.instance.reset();
  });

  test('register 注册屏幕侧核心依赖（LogService）', () async {
    await ScreenModules.register(GetIt.instance);
    expect(GetIt.instance.isRegistered<LogService>(), isTrue);
  });

  test('宿主先注册 CurrentSceneProvider，MsgModule 才能注册成功', () async {
    await ScreenModules.register(GetIt.instance);
    expect(GetIt.instance.isRegistered<CurrentSceneProvider>(), isTrue);
  });

  test('未注册 CurrentSceneProvider 时 register 失败（宿主必须先注册场景提供者）',
      () async {
    await GetIt.instance.reset();
    await expectLater(
      ScreenModules.register(GetIt.instance),
      throwsA(isA<StateError>()),
    );
  });
}
