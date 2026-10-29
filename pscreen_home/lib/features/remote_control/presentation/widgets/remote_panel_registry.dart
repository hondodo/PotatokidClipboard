import 'package:flutter/material.dart';
import 'package:pscreen_home/features/remote_control/presentation/widgets/home_remote_panel.dart';
import 'package:pscreen_home/features/remote_control/presentation/widgets/live_remote_panel.dart';
import 'package:pscreen_screen/core/network/realtime_channel.dart';

/// 面板构建上下文：被控设备 + 发送回调。
class RemotePanelContext {
  const RemotePanelContext({
    required this.account,
    required this.device,
    required this.online,
    required this.onCommand,
  });

  final String account;

  /// 设备已知状态（kind / scene / channels）；未知时为空。
  final RealtimeDeviceState? device;
  final bool online;

  /// 发送已构造好的命令信封（发到当前这台设备）。
  final ValueChanged<String> onCommand;

  /// 面板类型：`home` / `tv` / 空串（未知）。
  String get kind => device?.kind ?? '';
}

typedef RemotePanelBuilder = Widget Function(RemotePanelContext context);

/// 面板注册表：被控设备类型 → 遥控面板。
///
/// 默认注册 `home`（中控屏：场景按钮 + 直播遥控）与 `tv`（电视端：音量/静音 +
/// 「选择频道」展开）；未知类型回落电视面板，保证旧设备仍可操作。
class RemotePanelRegistry {
  RemotePanelRegistry._();

  static final Map<String, RemotePanelBuilder> _builders =
      <String, RemotePanelBuilder>{
    'home': (RemotePanelContext ctx) => HomeRemotePanel(panel: ctx),
    'tv': (RemotePanelContext ctx) =>
        LiveControlsPanel(panel: ctx, channelsLabel: '选择频道'),
  };

  /// 注册/覆盖某类型的面板（宿主可扩展）。
  static void register(String kind, RemotePanelBuilder builder) {
    final String key = kind.trim();
    if (key.isEmpty) return;
    _builders[key] = builder;
  }

  /// 按设备类型构建面板。
  static Widget build(RemotePanelContext context) {
    final RemotePanelBuilder builder =
        _builders[context.kind] ?? _builders['tv']!;
    return builder(context);
  }
}
