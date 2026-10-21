import 'package:pscreen_screen/features/msg/application/current_scene_provider.dart';

/// 中控屏场景描述。
///
/// 中控屏没有 Tab 外壳，场景恒为「中控台」；后续若引入可切换的媒体页，
/// 在此按当前路由给出更细的描述即可。
class HomeSceneProvider extends CurrentSceneProvider {
  const HomeSceneProvider();

  @override
  String describe() => '中控台';
}
