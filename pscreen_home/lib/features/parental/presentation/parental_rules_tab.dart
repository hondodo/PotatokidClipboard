import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pscreen_home/features/parental/data/parental_admin_api.dart';
import 'package:pscreen_home/features/parental/domain/parental_config.dart';
import 'package:pscreen_home/features/parental/presentation/parental_common.dart';
import 'package:pscreen_home/features/parental/presentation/parental_quiz_editor.dart';
import 'package:pscreen_home/features/parental/presentation/parental_sections.dart';
import 'package:pscreen_home/features/parental/presentation/parental_subpages.dart';

/// Tab 二：规则（孩子列表 + 全局设置）。
///
/// 孩子档案 CRUD 复用 [ChildrenSection]（含按档位显隐字段、题库入口）；
/// 全局解锁方式作为独立下钻页，避免与单台电视配置混在一起。
///
/// 过渡期（Phase 2）：页面顶部固定显示「正在配置：电视名 + 在线状态」，
/// 并提供就地切换电视的入口；切换期间进入加载态、禁用保存，避免把旧电视
/// 的配置误写进新电视（见 parental_page 的 `_switching` 守卫）。
class ParentalRulesView extends StatelessWidget {
  const ParentalRulesView({
    super.key,
    required this.config,
    required this.selected,
    required this.actions,
    required this.machines,
    required this.onSwitch,
    this.isSwitching = false,
    this.onAddDevice,
    this.onLogin,
  });

  final ParentalConfig config;
  final ParentalMachine? selected;
  final ParentalActions actions;

  /// 可切换的电视列表（用于就地切换，不影响「我的」页的列表入口）。
  final List<ParentalMachine> machines;

  /// 就地切换电视：由页面壳负责加载新电视配置并维护 `_switching` 守卫。
  final void Function(ParentalMachine machine) onSwitch;

  /// 正在切换电视（加载新配置中）：在此期间禁用一切写入口。
  final bool isSwitching;

  /// 无选中电视时透传给 [ChildrenSection] 的「添加电视」入口（可选）。
  final VoidCallback? onAddDevice;

  /// 无选中电视时透传的「登录已有家长号」入口（可选）。
  final VoidCallback? onLogin;

  Future<void> _openFirstChildQuiz(BuildContext context) async {
    if (selected == null || config.children.isEmpty) return;
    await ParentalQuizEditorSheet.show(
      context,
      deviceId: selected!.id,
      child: config.children.first,
    );
  }

  void _openSwitchSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext sheet) {
        final ThemeData theme = Theme.of(sheet);
        final List<ParentalMachine> tvs = machines;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Row(
                    children: <Widget>[
                      Text('切换配置目标', style: theme.textTheme.titleSmall),
                      const Spacer(),
                      if (tvs.isEmpty)
                        Text('暂无电视', style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                const Divider(height: 1),
                for (final ParentalMachine m in tvs)
                  ListTile(
                    leading: Icon(
                      m.online ? Icons.tv : Icons.tv_outlined,
                      color: m.online
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outline,
                    ),
                    title: Text(parentalTvName(m)),
                    subtitle: Text(m.online ? '在线' : '离线（可查看配置）'),
                    trailing: selected?.id == m.id
                        ? const Icon(Icons.check, size: 18)
                        : null,
                    onTap: selected?.id == m.id
                        ? null
                        : () {
                            Navigator.of(sheet).pop();
                            onSwitch(m);
                          },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool hasDevice = selected != null;
    final List<Widget> children = <Widget>[
      if (hasDevice)
        _ScopeHeader(
          machine: selected!,
          switching: isSwitching,
          onSwitch: () => _openSwitchSheet(context),
        ),
      ChildrenSection(
          config: config,
          onSave: actions.saveConfig,
          deviceId: selected?.id,
          shrinkWrap: true,
          onAddDevice: onAddDevice,
          onLogin: onLogin,
        ),
        const SizedBox(height: 12),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '全局设置',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('解锁方式'),
                  subtitle: hasDevice
                      ? Text(unlockModeLabel(config.unlockMode))
                      : const Text('需先选择电视'),
                  trailing: const Icon(Icons.chevron_right),
                  enabled: hasDevice,
                  onTap: hasDevice
                      ? () => unawaited(actions.push(ParentalRulesSettingsPage(
                            config: config,
                            machine: selected,
                            onSave: actions.saveConfig,
                          )))
                      : null,
                ),
                const Divider(height: 1),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('答题题库'),
                  subtitle: hasDevice
                      ? const Text('在「儿童档案」卡片里维护，按孩子分库')
                      : const Text('需先选择电视'),
                  trailing: const Icon(Icons.chevron_right),
                  enabled: hasDevice,
                  onTap: hasDevice
                      ? () => unawaited(_openFirstChildQuiz(context))
                      : null,
                ),
              ],
            ),
          ),
        ),
    ];
    Widget body = ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: children,
    );
    if (isSwitching) {
      // 切换电视加载新配置期间，禁止一切写入口，避免把旧配置误写进新电视。
      body = AbsorbPointer(child: body);
    }
    return Stack(
      children: <Widget>[
        body,
        if (isSwitching)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(),
          ),
      ],
    );
  }
}

/// 规则页顶部固定展示「正在配置：电视名 + 在线状态」，并提供就地切换入口。
class _ScopeHeader extends StatelessWidget {
  const _ScopeHeader({
    required this.machine,
    required this.switching,
    required this.onSwitch,
  });

  final ParentalMachine machine;
  final bool switching;
  final VoidCallback onSwitch;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool online = machine.online;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: <Widget>[
            Icon(
              online ? Icons.tv : Icons.tv_outlined,
              size: 22,
              color: online ? scheme.primary : scheme.outline,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '正在配置：${parentalTvName(machine)}',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: <Widget>[
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: online ? Colors.green : scheme.outline,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        online ? '在线' : '离线（可查看配置）',
                        style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            TextButton.icon(
              onPressed: switching ? null : onSwitch,
              icon: switching
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.swap_horiz, size: 18),
              label: const Text('切换'),
            ),
          ],
        ),
      ),
    );
  }
}
