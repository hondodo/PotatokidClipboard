import 'package:get_it/get_it.dart';
import 'package:pscreen_screen/core/parental/parental_state_controller.dart';

/// 儿童模式模块：注册 [ParentalStateController]（唯一持有者）。
///
/// 注册时 `await ensureLoaded()`，保证第一个页面 build 时配置/计时已就绪
///（选人页与锁屏直接读状态，无需再等网络）。
class ParentalModule {
  const ParentalModule._();

  static Future<void> register(GetIt it) async {
    final ParentalStateController controller = ParentalStateController.instance;
    // 顺序：先加载计时器持久化状态，再加载 parental 配置并同步进计时器——
    // ParentalStateController 是 activeChildIds 的唯一权威，其值必须最后写入。
    await controller.timer.ensureLoaded();
    await controller.ensureLoaded();
    it.registerSingleton<ParentalStateController>(controller);
  }

  static Future<void> unregister(GetIt it) async {
    if (it.isRegistered<ParentalStateController>()) {
      await it.unregister<ParentalStateController>();
    }
  }
}
