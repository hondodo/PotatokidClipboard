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

  /// 面板内轻提示（数字键回显「已发 N」/「请先输入频道号」）在本页用
  /// SnackBar 就地显示——页面是 push 上来的全屏页，外层 ParentalPage 的
  /// 提示胶囊被盖住看不到。
  void _showHint(BuildContext context, String message, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        duration: const Duration(milliseconds: 1600),
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? Theme.of(context).colorScheme.errorContainer : null,
      ));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title ?? '遥控')),
        // 数字键盘 + 原有控件纵向较长，包一层可滚动避免小屏溢出。
        body: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: TargetRemotePanel(
            account: account,
            title: title,
            onCommand: onCommand,
            onHint: (String message, {bool error = false}) =>
                _showHint(context, message, error: error),
          ),
        ),
      );
}
