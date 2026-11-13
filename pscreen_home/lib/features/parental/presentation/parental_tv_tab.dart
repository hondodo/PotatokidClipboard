import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pscreen_home/core/server/account_session.dart';
import 'package:pscreen_home/features/parental/data/parental_admin_api.dart';
import 'package:pscreen_home/features/parental/domain/parental_config.dart';
import 'package:pscreen_home/features/parental/presentation/parental_common.dart';
import 'package:pscreen_home/features/parental/presentation/parental_quiz_editor.dart';
import 'package:pscreen_home/features/parental/presentation/parental_subpages.dart';
import 'package:pscreen_home/features/parental/presentation/parental_unlock_section.dart';

/// Tab 三：电视（Phase 3 / Task 3.4）。
///
/// 每台电视是独立设备：绑定 / 扫码 / 重命名 / 解绑、直接进自己的遥控器，
/// 以及**本台设置**（儿童模式总开关 + 解锁方式与参数，CR-02 按 `deviceId` 独立）。
/// 规则（限额 / 时段 / 黑白名单）属于家庭档案，不在这里；这里只做设备侧配置。
class ParentalTvView extends StatelessWidget {
  const ParentalTvView({
    super.key,
    required this.machines,
    required this.selected,
    required this.config,
    required this.actions,
  });

  final List<ParentalMachine> machines;
  final ParentalMachine? selected;
  final ParentalConfig config;
  final ParentalActions actions;

  bool get _readOnly => AccountSession.isAdmin;

  Future<void> _openQuiz(BuildContext context) async {
    final ParentalMachine? tv = selected;
    if (tv == null || config.children.isEmpty) return;
    await ParentalQuizEditorSheet.show(
      context,
      deviceId: tv.id,
      child: config.children.first,
    );
  }

  void _sendRemoteTo(ParentalMachine machine) {
    final String to = machine.commAccount.isEmpty ? machine.id : machine.commAccount;
    unawaited(actions.push(ParentalRemotePage(
      account: to,
      title: parentalTvName(machine),
      onCommand: (String command) => actions.sendRemoteCommand(to, command),
    )));
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    if (machines.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: <Widget>[
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('还没有绑定电视', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 6),
                  Text(
                    '绑定电视后可在这里遥控、设置儿童模式与解锁方式，并按台分配家庭档案。',
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      FilledButton.tonalIcon(
                        onPressed: () => unawaited(actions.openDeviceManager()),
                        icon: const Icon(Icons.qr_code_scanner, size: 18),
                        label: const Text('添加 / 扫码绑定电视'),
                      ),
                      if (!actions.hasClaimedAccount)
                        OutlinedButton.icon(
                          onPressed: () => unawaited(actions.openLoginExisting()),
                          icon: const Icon(Icons.login, size: 18),
                          label: const Text('登录已有家长号'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: <Widget>[
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text('我的电视',
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                    const Spacer(),
                    Text('${machines.length} 台'),
                  ],
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '点选一台作为本台设置的目标；儿童模式与解锁方式仅对该台生效。',
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
                  ),
                ),
                for (final ParentalMachine machine in machines)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      machine.id == selected?.id ? Icons.tv : Icons.tv_outlined,
                      color: machine.id == selected?.id ? scheme.primary : null,
                    ),
                    title: Text(
                      parentalTvName(machine),
                      style: machine.id == selected?.id
                          ? TextStyle(color: scheme.primary, fontWeight: FontWeight.w600)
                          : null,
                    ),
                    subtitle: Text(
                      '${machine.online ? '在线' : '离线'}'
                      '${machine.id == selected?.id ? ' · 当前设置目标' : ''}',
                    ),
                    onTap: () => actions.selectDevice(machine),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        IconButton(
                          tooltip: '遥控 ${parentalTvName(machine)}',
                          icon: const Icon(Icons.control_camera, size: 20),
                          onPressed: () => _sendRemoteTo(machine),
                        ),
                        if (!_readOnly)
                          IconButton(
                            tooltip: '重命名（仅自己可见）',
                            icon: const Icon(Icons.drive_file_rename_outline, size: 20),
                            onPressed: () => actions.renameMachine(machine),
                          ),
                        if (!_readOnly)
                          IconButton(
                            tooltip: '解绑',
                            icon: const Icon(Icons.link_off, size: 20),
                            onPressed: () => actions.unbind(machine.id),
                          ),
                      ],
                    ),
                  ),
                if (!_readOnly)
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
                  )
                else
                  Text(
                    '绑定 / 解绑电视由家长操作',
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (selected == null)
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('先在上方点选一台电视，再设置本台的儿童模式与解锁方式。',
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline)),
            ),
          )
        else ...<Widget>[
          Card(
            margin: EdgeInsets.zero,
            child: SwitchListTile(
              contentPadding: const EdgeInsets.fromLTRB(14, 4, 10, 4),
              secondary: Icon(Icons.child_care_outlined, color: scheme.primary),
              title: const Text('儿童模式'),
              subtitle: Text(
                _readOnly
                    ? '只读代管：不可修改'
                    : '仅对「${parentalTvName(selected!)}」生效',
              ),
              value: config.mode == 'on',
              onChanged: _readOnly
                  ? null
                  : (bool value) => unawaited(
                        actions.saveConfig(config.copyWith(mode: value ? 'on' : 'off')),
                      ),
            ),
          ),
          const SizedBox(height: 12),
          ParentalUnlockSection(
            key: ValueKey<String>(
              '${selected?.id ?? 'none'}:${config.ownerAccount}'
              ':${config.unlockMode}:${config.pin}',
            ),
            config: config,
            machine: selected,
            onSave: actions.saveConfig,
            onOpenQuiz: () => unawaited(_openQuiz(context)),
            readOnly: _readOnly,
          ),
        ],
      ],
    );
  }
}
