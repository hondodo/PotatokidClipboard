/// 首页「当前频道提示」的控制器（纯字段，不派发通知）。
///
/// 首页导航条隐藏时，壳层「左/右」键由这里路由为切换当前频道的源。
/// 只存回调；真正的切源与提示显示由 [LivePlayerWidget] 注册实现。
class HomeNowPlayingController {
  HomeNowPlayingController._();

  /// 全局单例。
  static final HomeNowPlayingController instance = HomeNowPlayingController._();

  /// 切源回调（播放器注册），delta 为 +1/-1。
  void Function(int delta)? onSwitchSource;

  /// 左/右切换当前频道源。
  void switchSource(int delta) => onSwitchSource?.call(delta);

  /// 显示当前频道名提示的回调（播放器注册）。
  void Function()? onShowToast;

  /// 让播放器在左下角显示当前频道名（菜单键呼出列表时用）。
  void showToast() => onShowToast?.call();
}