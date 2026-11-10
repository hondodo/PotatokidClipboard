import 'package:flutter/material.dart';
import 'package:pscreen_screen/core/media/video_aspect_mode.dart';

/// 首页遥控唯一交互层。频道列表和操作胶囊都属于 [quickControls]。
enum HomeRemoteLayer { fullscreen, channelInfo, quickControls, appBar }

/// 应用级全局状态（不可变，通过 copyWith 更新）
class AppState {
  const AppState._({
    required this.themeMode,
    required this.isChromeVisible,
    required this.isChromePeek,
    required this.showFloatingRemote,
    required this.homeRemoteLayer,
    required this.hwdecEnabled,
    required this.aspectMode,
    required this.weatherCity,
    required this.removeInvalidSources,
    required this.backgroundPlayback,
  });

  /// 初始状态：主题默认**深色**（用户可在「我的」页改为浅色/跟随系统），
  /// 导航条默认可见，频道条默认隐藏，避免两个遥控交互层同时出现，
  /// 悬浮遥控器默认**隐藏**（需在「我的」页开启），
  /// 硬解默认**关闭**（TV 设备兼容性考虑，用户可在「我的」页开启），
  /// 清理失效源默认**关闭**。
  factory AppState.initial() => const AppState._(
    themeMode: ThemeMode.dark,
    isChromeVisible: true,
    isChromePeek: false,
    showFloatingRemote: false,
    homeRemoteLayer: HomeRemoteLayer.appBar,
    hwdecEnabled: false,
    aspectMode: VideoAspectMode.original,
    weatherCity: '',
    removeInvalidSources: false,
    backgroundPlayback: false,
  );

  final ThemeMode themeMode;

  /// AppBar 与底部导航栏（顶部 tab 条）是否可见（false 时进入沉浸式全屏）
  final bool isChromeVisible;

  /// 导航条的「短暂预览」态：仅用于显示，**不参与焦点/切页**。
  /// 时间页按键时短暂露出导航条，提示用户菜单键的位置，但不让 tab 变为
  /// 可聚焦（避免显示瞬间抢走正文焦点或误切页）。
  final bool isChromePeek;

  /// 是否显示悬浮遥控器蒙层（手机调试用）
  final bool showFloatingRemote;

  final HomeRemoteLayer homeRemoteLayer;

  /// 兼容播放器绘制层读取；显隐只由 [homeRemoteLayer] 派生。
  bool get showChannels => homeRemoteLayer == HomeRemoteLayer.quickControls;

  /// 是否启用硬件解码（关闭时使用 FFmpeg 软解，TV 设备兼容性更好）
  final bool hwdecEnabled;

  /// 视频画面显示模式（原始/拉伸/16:9/4:3/21:9）
  final VideoAspectMode aspectMode;

  /// 天气城市名；空串表示「自动」（IP 反查定位）
  final String weatherCity;

  /// 是否开启「清理失效源」（连续打不开的地址会被记录并移除）
  final bool removeInvalidSources;

  /// 是否开启「后台播放」（关闭时 App 退到后台即暂停，默认关闭）
  final bool backgroundPlayback;

  AppState copyWith({
    ThemeMode? themeMode,
    bool? isChromeVisible,
    bool? isChromePeek,
    bool? showFloatingRemote,
    HomeRemoteLayer? homeRemoteLayer,
    bool? hwdecEnabled,
    VideoAspectMode? aspectMode,
    String? weatherCity,
    bool? removeInvalidSources,
    bool? backgroundPlayback,
  }) => AppState._(
        themeMode: themeMode ?? this.themeMode,
        isChromeVisible: isChromeVisible ?? this.isChromeVisible,
        isChromePeek: isChromePeek ?? this.isChromePeek,
        showFloatingRemote: showFloatingRemote ?? this.showFloatingRemote,
        homeRemoteLayer: homeRemoteLayer ?? this.homeRemoteLayer,
        hwdecEnabled: hwdecEnabled ?? this.hwdecEnabled,
        aspectMode: aspectMode ?? this.aspectMode,
        weatherCity: weatherCity ?? this.weatherCity,
        removeInvalidSources: removeInvalidSources ?? this.removeInvalidSources,
        backgroundPlayback: backgroundPlayback ?? this.backgroundPlayback,
      );
}
