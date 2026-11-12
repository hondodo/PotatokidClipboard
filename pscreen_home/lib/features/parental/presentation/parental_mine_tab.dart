import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pscreen_home/core/server/account_session.dart';
import 'package:pscreen_home/features/parental/data/parental_admin_api.dart';
import 'package:pscreen_home/features/parental/domain/parental_config.dart';
import 'package:pscreen_home/features/parental/domain/parental_share.dart';
import 'package:pscreen_home/features/parental/presentation/parental_common.dart';
import 'package:pscreen_home/features/parental/presentation/parental_mine_cards.dart';
import 'package:pscreen_home/features/parental/presentation/parental_quiz_editor.dart';
import 'package:pscreen_home/features/parental/presentation/parental_subpages.dart';
import 'package:pscreen_home/features/parental/presentation/parental_unlock_section.dart';
import 'package:pscreen_screen/core/network/realtime_channel.dart';
import 'package:pscreen_screen/core/utils/app_version.dart';

/// Tab 三：我的（账号 / 我在电视上的名字 / 我的电视 / 档案共享 / 解锁方式 / 连接与更新）。
///
/// 原右上角「设置」弹层的内容已全部并入本页，右上角只留解锁铃铛 + 刷新。
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
    this.channelAccount = '',
    this.onEditAccount,
    this.channel,
    this.version,
  });

  final List<ParentalMachine> machines;
  final ParentalMachine? selected;
  final ParentalConfig config;

  /// 家长号（管理登录身份，可改、跨设备）。
  final String myAccount;

  /// 本机实时通道派生号（设备身份，只读，永不改名/禁用）。
  final String channelAccount;

  final ParentalActions actions;

  /// 去「设置登录名」页；由页面壳注入路由跳转，便于无 GoRouter 的测试渲染。
  final VoidCallback? onEditAccount;

  /// 连接与更新卡的依赖注入（测试用；正式运行从全局依赖读取）。
  final RealtimeChannel? channel;
  final AppVersion? version;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: <Widget>[
        // ① 账号：家长号（可改/跨设备）+ 本机实时通道号（只读/不可改）两层分开。
        //    权限自愈由顶栏刷新覆盖，不再显示「当前角色 / 账号与权限」。
        ParentalAccountCard(
          account: myAccount,
          channelAccount: channelAccount,
          onEdit: onEditAccount,
          onLearnMore: onEditAccount,
        ),
        const SizedBox(height: 12),
        // ② 我在电视上的名字（原设置弹窗的「更改名称」搬来）。
        const ParentalDisplayNameCard(),
        const SizedBox(height: 12),
        // ③ 我的电视
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
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '点选一台作为当前配置目标；规则、解锁方式作用于选中的电视。',
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
                  ),
                ),
                // 顶部下拉去掉后，设备选择 / 重命名 / 解绑统一收敛到这里。
                for (final ParentalMachine machine in machines)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      machine.id == selected?.id
                          ? Icons.tv
                          : Icons.tv_outlined,
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
                      '${machine.id == selected?.id ? ' · 当前配置目标' : ''}',
                    ),
                    onTap: () => actions.selectDevice(machine),
                    // 遥控是设备级操作，常驻可见（与原孩子卡遥控一致，不受角色限制）；
                    // 目标就是这一行对应的电视，不再需要从实时事件推断。
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        IconButton(
                          tooltip: '遥控 ${parentalTvName(machine)}',
                          icon: const Icon(Icons.control_camera, size: 20),
                          onPressed: () {
                            // 把「被点击这台」的派生号固化进闭包，遥控命令发到
                            // 这一台，而不是当前配置目标 _selected（多台时曾发错台）。
                            final String to = machine.commAccount.isEmpty
                                ? machine.id
                                : machine.commAccount;
                            unawaited(actions.push(ParentalRemotePage(
                              account: to,
                              title: parentalTvName(machine),
                              onCommand: (String command) =>
                                  actions.sendRemoteCommand(to, command),
                            )));
                          },
                        ),
                        if (AccountSession.isParent)
                          IconButton(
                            tooltip: '重命名（仅自己可见）',
                            icon: const Icon(Icons.drive_file_rename_outline, size: 20),
                            onPressed: () => actions.renameMachine(machine),
                          ),
                        if (AccountSession.isParent)
                          IconButton(
                            tooltip: '解绑',
                            icon: const Icon(Icons.link_off, size: 20),
                            onPressed: () => actions.unbind(machine.id),
                          ),
                      ],
                    ),
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
        // ④ 档案共享：引用代替复制。主本留在原电视，引用方只读；
        //    来源失效保留占位，不级联删。入口与 HTML 设计稿一致，从「我的」进入。
        _buildShareCard(context, theme),
        const SizedBox(height: 12),
        // ⑤ 解锁方式：4 张说明卡 + 顶部「当前配置目标」标注（对齐设计稿）。
        //    PIN / 题库入口就地给出，不用上翻找设备或跨 Tab。
        ParentalUnlockSection(
          // 配置变化（含换设备）时重建编辑态，回显最新解锁方式与 PIN。
          key: ValueKey<String>(
            '${selected?.id ?? 'none'}:${config.ownerAccount}'
            ':${config.unlockMode}:${config.pin}',
          ),
          config: config,
          machine: selected,
          onSave: actions.saveConfig,
          onOpenQuiz: () => unawaited(_openQuiz(context)),
        ),
        const SizedBox(height: 12),
        // ⑥ 连接与更新（原设置弹窗的通道状态 + 版本更新搬来）。
        ParentalConnectionCard(channel: channel, version: version),
      ],
    );
  }

  /// 答题解锁的题库入口：就地打开当前配置目标设备的第一个孩子题库。
  /// 与规则页 `_openFirstChildQuiz` 同口径；多孩子取第一个，服务端按规则合并。
  Future<void> _openQuiz(BuildContext context) async {
    if (selected == null || config.children.isEmpty) return;
    await ParentalQuizEditorSheet.show(
      context,
      deviceId: selected!.id,
      child: config.children.first,
    );
  }

  Widget _buildShareCard(BuildContext context, ThemeData theme) {
    final ColorScheme scheme = theme.colorScheme;
    final ParentalMachine? target =
        selected ?? (machines.isEmpty ? null : machines.first);
    final int importedCount = target?.shareView?.imported.length ?? 0;
    final int brokenCount = target?.shareView?.imported
            .where((ParentalShareImported item) => item.isBroken)
            .length ??
        0;
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
        leading: Icon(Icons.family_restroom_outlined, color: scheme.primary),
        title: const Text('档案共享'),
        subtitle: Text(
          target == null
              ? '先绑定一台电视后，可跨电视 / 跨家长引用档案'
              : brokenCount > 0
                  ? '当前电视：$importedCount 份引用，其中 $brokenCount 份失效待重新选择'
                  : '当前电视：$importedCount 份引用 · 主本在别处，本台只读',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: target == null
            ? null
            : () => actions.openShareManagement(target),
      ),
    );
  }
}
