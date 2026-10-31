import 'package:flutter/foundation.dart';
import 'package:potatokid_screen/features/app/application/app_tab_controller.dart';
import 'package:pscreen_screen/features/iptv/application/channel_info_provider.dart';
import 'package:pscreen_screen/features/iptv/application/live_channel_controller.dart';
import 'package:pscreen_screen/features/msg/application/current_scene_provider.dart';

/// 电视端场景描述。
///
/// 场景本身（kind/title）由当前 Tab 决定：直播 / 时间页 / 屏保 / 设置。
/// 但 `MainApp` 用 `StatefulShellRoute.indexedStack`，离开首页时首页分支
/// 仍然挂载、频道仍在播放——所以**每个 Tab 都随场景带上当前频道**，
/// 让遥控端在任意页面打开频道列表都能定位并高亮当前项。
///
/// 直播页走 `channelName` 字段；其余 Tab 走 `extra`（原因见
/// [_channelExtra]：不参与 `SceneSnapshot.key`，避免非直播页换台时
/// 误发「场景切换：<页名>」上报）。
class TvSceneProvider extends CurrentSceneProvider {
  const TvSceneProvider();

  /// Tab 或频道变化都会触发场景推送（结构合并为一个 Listenable）。
  static final Listenable _changes = Listenable.merge(<Listenable>[
    AppTabController.changes,
    LiveChannelController.instance,
  ]);

  @override
  String describe() {
    if (AppTabController.branchIndex == 0) {
      final String? name = ChannelInfoProvider.instance
          .nameAt(LiveChannelController.instance.index);
      if (name != null) return name;
    }
    return AppTabController.pageName;
  }

  @override
  SceneSnapshot snapshot() {
    switch (AppTabController.branchIndex) {
      case 0:
        final int index = LiveChannelController.instance.index;
        return SceneSnapshot(
          kind: SceneKind.live,
          route: 'home',
          title: ChannelInfoProvider.instance.nameAt(index) ?? '主页',
          channelName: ChannelInfoProvider.instance.nameAt(index),
          extra: <String, Object?>{'channelIndex': index},
        );
      case 1:
        return SceneSnapshot(
          kind: SceneKind.clock,
          route: 'time',
          title: '时间页',
          extra: _channelExtra,
        );
      case 2:
        return SceneSnapshot(
          kind: SceneKind.screensaver,
          route: 'screensaver',
          title: '屏保',
          extra: _channelExtra,
        );
      default:
        return SceneSnapshot(
          kind: SceneKind.settings,
          route: 'profile',
          title: '设置',
          extra: _channelExtra,
        );
    }
  }

  /// 非直播 Tab 随场景携带的当前频道（`toJson` 把 `extra` 展平到顶层，
  /// 与直播页的 `channelName` 字段同名同形，遥控端无需区分来源）。
  ///
  /// 走 `extra` 而不是 `channelName` 字段：`SceneSnapshot.key` 含字段
  /// channelName，非直播页带该字段会在换台时让 key 变化，误发
  /// 「场景切换：<页名>」上报；`extra` 不参与 key，只进上报 JSON。
  static Map<String, Object?> get _channelExtra {
    final int index = LiveChannelController.instance.index;
    final String? name = ChannelInfoProvider.instance.nameAt(index);
    if (name == null) return const <String, Object?>{};
    return <String, Object?>{'channelName': name, 'channelIndex': index};
  }

  @override
  Listenable get changes => _changes;
}
