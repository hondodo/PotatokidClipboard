/// 当前所在场景的描述（供上行上报使用）。
///
/// 抽象原因：电视端有 4-tab 外壳（页名由 Tab 决定），中控屏没有 Tab
/// （页名恒为「中控台」）。共享包不能依赖任一宿主的导航实现。
abstract class CurrentSceneProvider {
  const CurrentSceneProvider();

  /// 当前场景的可读描述，例：「正在收看 CCTV-1」「停留在中控台」。
  String describe();
}
