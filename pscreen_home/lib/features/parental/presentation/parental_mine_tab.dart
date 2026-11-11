import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pscreen_home/core/server/account_session.dart';
import 'package:pscreen_home/features/parental/data/parental_admin_api.dart';
import 'package:pscreen_home/features/parental/domain/parental_config.dart';
import 'package:pscreen_home/features/parental/presentation/parental_common.dart';
import 'package:pscreen_home/features/parental/presentation/parental_sections.dart';

/// Tab 三：我的（账号权限 / 我的电视 / 解锁设置）。
///
/// 只保留家长需要的设置，HA 网格、布局、IPTV、频道、场景上报等中控台设置
/// 不出现在这里。
class ParentalMineView extends StatelessWidget {
  const ParentalMineView({
    super.key,
    required this.machines,
    required this.selected,
    required this.config,
    required this.myAccount,
    required this.actions,
  });

  final List<ParentalMachine> machines;
  final ParentalMachine? selected;
  final ParentalConfig config;
  final String myAccount;
  final ParentalActions actions;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: <Widget>[
        // 账号与权限
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '账号与权限',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    const Text('当前角色'),
                    const Spacer(),
                    Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text(AccountSession.role.isEmpty ? '未确定' : AccountSession.role),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                SelectableText('账号：${myAccount.isEmpty ? '检测中…' : myAccount}'),
                const SizedBox(height: 8),
                FilledButton.tonal(
                  onPressed: () => unawaited(actions.refreshPermission()),
                  child: const Text('重新检查权限'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // 我的电视
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text(
                      '我的电视',
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    Text('${machines.length} 台'),
                  ],
                ),
                const SizedBox(height: 8),
                for (final ParentalMachine machine in machines)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.tv_outlined),
                    title: Text(parentalTvName(machine)),
                    subtitle: Text(machine.online ? '在线' : '离线'),
                    trailing: AccountSession.isParent
                        ? IconButton(
                            tooltip: '解绑',
                            icon: const Icon(Icons.link_off),
                            onPressed: () => actions.unbind(machine.id),
                          )
                        : null,
                  ),
                FilledButton.tonal(
                  onPressed: () => unawaited(actions.openDeviceManager()),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(Icons.qr_code_scanner, size: 16),
                      SizedBox(width: 4),
                      Text('添加 / 解绑电视'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        ParentalSettingsSection(
          // 配置变化（含换设备）时重建编辑态，回显最新解锁方式与 PIN。
          key: ValueKey<String>(
            '${selected?.id ?? 'none'}:${config.ownerAccount}'
            ':${config.unlockMode}:${config.pin}',
          ),
          config: config,
          machine: selected,
          onSave: actions.saveConfig,
          shrinkWrap: true,
        ),
      ],
    );
  }
}
