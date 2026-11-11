import 'package:flutter/material.dart';
import 'package:pscreen_home/features/parental/data/parental_admin_api.dart';
import 'package:pscreen_home/features/parental/domain/parental_config.dart';
import 'package:pscreen_home/features/parental/presentation/parental_sections.dart';
import 'package:pscreen_home/features/remote_control/presentation/widgets/target_remote_panel.dart';
import 'package:pscreen_screen/core/network/realtime_channel.dart';

/// 子页面：把家长端现有 section / 面板包成可 `Navigator.push` 的全屏页，
/// 让「今天 / 规则」首页上的入口（去处理 / 遥控 / 解锁方式）能下钻，
/// 而不再依赖底部 5 个 Tab 各自承载。三个 section 复用现有实现，避免重复。

/// 解锁中心（原「解锁」Tab 的内容，作为下钻页）。
class ParentalUnlockPage extends StatelessWidget {
  const ParentalUnlockPage({
    super.key,
    required this.events,
    required this.onUnlock,
    this.machine,
    this.acks = const <RealtimeEvent>[],
    this.isAdmin = false,
    this.myAccount = '',
    this.onManageDevices,
  });

  final List<RealtimeEvent> events;
  final Future<void> Function(RealtimeEvent event) onUnlock;
  final ParentalMachine? machine;
  final List<RealtimeEvent> acks;
  final bool isAdmin;
  final String myAccount;
  final VoidCallback? onManageDevices;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('解锁中心')),
        body: UnlockSection(
          events: events,
          onUnlock: onUnlock,
          machine: machine,
          acks: acks,
          isAdmin: isAdmin,
          myAccount: myAccount,
          onManageDevices: onManageDevices,
        ),
      );
}

/// 观看历史（原「观看者」Tab 的内容，作为下钻页）。
class ParentalWatchPage extends StatelessWidget {
  const ParentalWatchPage({
    super.key,
    required this.config,
    this.machine,
    required this.watchEvents,
    required this.activeEvents,
    this.sessions = const <ParentalSession>[],
  });

  final ParentalConfig config;
  final ParentalMachine? machine;
  final List<RealtimeEvent> watchEvents;
  final List<RealtimeEvent> activeEvents;
  final List<ParentalSession> sessions;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('观看记录')),
        body: WatchSection(
          config: config,
          machine: machine,
          watchEvents: watchEvents,
          activeEvents: activeEvents,
          sessions: sessions,
        ),
      );
}

/// 解锁方式设置（原「设置」Tab 的全局解锁参数，作为下钻页）。
class ParentalRulesSettingsPage extends StatelessWidget {
  const ParentalRulesSettingsPage({
    super.key,
    required this.config,
    this.machine,
    required this.onSave,
  });

  final ParentalConfig config;
  final ParentalMachine? machine;
  final Future<void> Function(ParentalConfig next) onSave;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('解锁方式')),
        body: ParentalSettingsSection(
          key: ValueKey<String>('${machine?.id ?? 'none'}:${config.ownerAccount}'
              ':${config.unlockMode}:${config.pin}'),
          config: config,
          machine: machine,
          onSave: onSave,
        ),
      );
}

/// 遥控：把 `TargetRemotePanel` 包成全屏页（原「遥控」Tab 的能力收进孩子卡
/// 的快捷按钮后，从这里进入）。
class ParentalRemotePage extends StatelessWidget {
  const ParentalRemotePage({
    super.key,
    required this.account,
    required this.onCommand,
    this.title,
  });

  final String account;
  final Future<void> Function(String command) onCommand;
  final String? title;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title ?? '遥控')),
        body: TargetRemotePanel(
          account: account,
          title: title,
          onCommand: onCommand,
        ),
      );
}
