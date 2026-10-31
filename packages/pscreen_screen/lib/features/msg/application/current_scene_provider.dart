import 'package:flutter/foundation.dart';

/// 场景类型。宿主按自己的导航/播放状态映射。
enum SceneKind {
  unknown,
  home,
  live,
  clock,
  screensaver,
  weather,
  settings,
  deviceDetail,
  other,
}

/// 当前场景的结构化快照。
///
/// 与 [CurrentSceneProvider.describe] 的纯文本相比，快照能区分
/// 「直播-xx频道」「屏保」「手动时钟」「设备详情」等语义，
/// 便于服务端按场景统计和检索。
@immutable
class SceneSnapshot {
  const SceneSnapshot({
    required this.kind,
    this.route = '',
    required this.title,
    this.channelName,
    this.deviceId,
    this.deviceName,
    this.areaId,
    this.areaName,
    this.extra = const <String, Object?>{},
  });

  final SceneKind kind;
  final String route;
  final String title;
  final String? channelName;
  final String? deviceId;
  final String? deviceName;
  final String? areaId;
  final String? areaName;
  final Map<String, Object?> extra;

  /// 用于判断场景是否真的发生变化，避免同页重建重复上报。
  String get key => <String>[
        kind.name,
        route,
        channelName ?? '',
        deviceId ?? '',
        areaId ?? '',
        title,
      ].join('|');

  Map<String, Object?> toJson() => <String, Object?>{
        'kind': kind.name,
        'route': route,
        'title': title,
        if (channelName != null && channelName!.isNotEmpty)
          'channelName': channelName,
        if (deviceId != null && deviceId!.isNotEmpty) 'deviceId': deviceId,
        if (deviceName != null && deviceName!.isNotEmpty)
          'deviceName': deviceName,
        if (areaId != null && areaId!.isNotEmpty) 'areaId': areaId,
        if (areaName != null && areaName!.isNotEmpty) 'areaName': areaName,
        if (extra.isNotEmpty) ...extra,
      };

  @override
  String toString() => 'SceneSnapshot(${toJson()})';
}

/// 当前所在场景的描述（供上行上报使用）。
///
/// 抽象原因：电视端有 4-tab 外壳（页名由 Tab 决定），中控屏没有 Tab
/// （页名由路由决定）。共享包不能依赖任一宿主的导航实现。
///
/// **场景描述完全由宿主决定**。旧宿主只需实现 [describe] 即可保持兼容；
/// 需要结构化上报的宿主应覆盖 [snapshot]，并通过 [changes] 发出变更通知。
abstract class CurrentSceneProvider {
  const CurrentSceneProvider();

  /// 当前场景的可读描述，例：「直播 CCTV-1」「停留在主页」。
  ///
  /// 默认使用 [snapshot] 的 title；只覆盖 [describe] 的旧实现不受影响。
  String describe() => snapshot().title;

  /// 当前场景的结构化快照。
  ///
  /// 默认把 [describe] 包装成 [SceneKind.unknown]，用于兼容电视端等旧实现。
  SceneSnapshot snapshot() => SceneSnapshot(
        kind: SceneKind.unknown,
        title: describe(),
      );

  /// 场景可能发生变化时触发（路由切换、播放频道变化、进入/退出屏保等）。
  ///
  /// 返回 null 表示宿主不支持变更通知；上报服务会退化为只在启动时采集一次。
  Listenable? get changes => null;
}
