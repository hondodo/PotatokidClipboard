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

  /// 显式显示频道面板。供遥控交互层进入频道模式时调用。
  void Function()? onShowChannelPanel;

  /// 显式关闭频道面板。返回键逐层退出时不能使用 toggle，否则频道名提示
  /// 已先消失时可能把列表反向打开。
  void Function()? onHideChannelPanel;

  void showChannelPanel() => onShowChannelPanel?.call();

  void hideChannelPanel() => onHideChannelPanel?.call();
}
