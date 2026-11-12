import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pscreen_home/core/di/injection.dart';
import 'package:pscreen_home/features/settings/presentation/widgets/realtime_status_section.dart';
import 'package:pscreen_home/features/update/presentation/update_pill.dart';
import 'package:pscreen_screen/core/network/realtime_channel.dart';
import 'package:pscreen_screen/core/update/app_update_controller.dart';
import 'package:pscreen_screen/core/utils/account_profile_api.dart';
import 'package:pscreen_screen/core/utils/app_settings.dart';
import 'package:pscreen_screen/core/utils/app_version.dart';

/// 「我的」页的卡片集合：账号 / 我在电视上的名字 / 连接与更新。
///
/// 从原右上角「设置」弹层（ParentalRealtimeSettingsSheet）搬来并重组：
/// - 「设置登录名」→ 账号卡右侧铅笔，跳 claim 页；
/// - 「更改名称」（displayName）→ 家长端名称卡；
/// - 「遥控通道状态 / 网关」「版本与更新」→ 连接与更新卡。
/// 这样家长所有设置集中在一页，右上角不再需要设置齿轮。

/// ① 账号卡：**两层身份彻底分开**，互不替代。
///
/// - 家长号（[account]）：可改、跨设备的「人」身份，决定能看哪几台电视；
///   右侧铅笔进「家长号与跨设备」页设置。
/// - 本机实时通道号（[channelAccount]）：设备派生号，只读，永不改名/禁用；
///   实时通道、心跳、遥控都靠它。改家长号不会动它。
///
/// 不显示「当前角色 / 账号与权限」大块——权限自愈由顶栏刷新覆盖。
class ParentalAccountCard extends StatelessWidget {
  const ParentalAccountCard({
    super.key,
    required this.account,
    this.channelAccount = '',
    this.onEdit,
    this.onLearnMore,
  });

  /// 家长号（管理登录身份）。
  final String account;

  /// 本机实时通道派生号（设备身份，只读）。
  final String channelAccount;

  /// 去「家长号与跨设备」页。纯回调，便于无 GoRouter 的测试环境渲染。
  final VoidCallback? onEdit;

  /// 去「家长号怎么跨设备」说明页；缺省时与 [onEdit] 同目标。
  final VoidCallback? onLearnMore;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(Icons.account_circle_outlined, size: 22, color: scheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('家长号（跨设备身份）', style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline)),
                      const SizedBox(height: 2),
                      SelectableText(
                        account.isEmpty ? '未设置（使用设备号）' : account,
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: scheme.primary),
                        maxLines: 1,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'A/B 手机用同一个家长号登录，看到同一批电视与档案。',
                        style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
                      ),
                    ],
                  ),
                ),
                IconButton(tooltip: '设置家长号', icon: const Icon(Icons.edit_outlined, size: 20), onPressed: onEdit),
              ],
            ),
            // 保留下同注释，但不要给用户看到
            // const Divider(height: 18),
            // Row(
            //   crossAxisAlignment: CrossAxisAlignment.start,
            //   children: <Widget>[
            //     Icon(Icons.phonelink_lock_outlined, size: 20, color: scheme.outline),
            //     const SizedBox(width: 12),
            //     Expanded(
            //       child: Column(
            //         crossAxisAlignment: CrossAxisAlignment.start,
            //         children: <Widget>[
            //           Text(
            //             '本机实时通道号（设备身份 · 只读）',
            //             style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
            //           ),
            //           const SizedBox(height: 2),
            //           SelectableText(
            //             channelAccount.isEmpty ? '检测中…' : channelAccount,
            //             style: theme.textTheme.bodyMedium?.copyWith(
            //               fontFamily: 'monospace',
            //               fontSize: 12,
            //             ),
            //             maxLines: 1,
            //           ),
            //           const SizedBox(height: 3),
            //           Text(
            //             '设备身份证，永不改名、不禁用；改家长号不会动它。',
            //             style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
            //           ),
            //         ],
            //       ),
            //     ),
            //   ],
            // ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: onLearnMore ?? onEdit,
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                child: Text('家长号怎么跨设备 ›', style: theme.textTheme.bodySmall),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ② 家长端名称卡：你在电视上、解锁请求里显示的家长名字。
///
/// 保存后写本机 AppSettings 并同步服务端（电视据此认出是哪位家长）；
/// 留空回落显示账号。注意这不是电视别名，也不是登录账号。
///
/// [initialName] 仅供测试注入，避免无头环境触发 SharedPreferences 读取；
/// 正式运行传 null，由 initState 异步回显已保存值。
class ParentalDisplayNameCard extends StatefulWidget {
  const ParentalDisplayNameCard({super.key, this.initialName});

  final String? initialName;

  @override
  State<ParentalDisplayNameCard> createState() => _ParentalDisplayNameCardState();
}

class _ParentalDisplayNameCardState extends State<ParentalDisplayNameCard> {
  late final TextEditingController _controller;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName ?? '');
    if (widget.initialName == null) unawaited(_loadSaved());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadSaved() async {
    await AppSettings.instance.ensureLoaded();
    if (!mounted || _controller.text.isNotEmpty) return;
    final String saved = AppSettings.instance.displayName;
    if (saved.isNotEmpty) setState(() => _controller.text = saved);
  }

  Future<void> _save() async {
    final String name = _controller.text.trim();
    setState(() => _saving = true);
    await AppSettings.instance.setDisplayName(name);
    bool synced = false;
    try {
      synced = await AccountProfileApi.updateDisplayName(name);
    } catch (_) {
      synced = false;
    }
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(synced ? '名称已保存（电视端会显示这个名字）' : '名称已保存到本机，服务端同步失败（联网后重试）'),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('我在电视上的名字', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(
              '电视和解锁请求里会显示这个名字，方便认出是哪位家长；留空则显示账号。'
              '注意：这不是电视的备注名，也不是登录账号。',
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                labelText: '显示名',
                hintText: '例如：小米10s家长端',
                helperText: '仅用于展示，不影响账号与连接',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              maxLines: 1,
            ),
            const SizedBox(height: 10),
            FilledButton.tonalIcon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save_rounded, size: 18),
              label: Text(_saving ? '保存中…' : '保存名字'),
            ),
          ],
        ),
      ),
    );
  }
}

/// ⑤ 连接与更新卡：遥控通道状态、网关、版本与更新。
///
/// 从原「设置」弹层搬来。[channel] / [version] 可注入以便测试；正式运行传 null，
/// 内部从全局依赖读取——若依赖尚未注册（如无头测试），降级显示占位而不抛异常。
class ParentalConnectionCard extends StatelessWidget {
  const ParentalConnectionCard({super.key, this.channel, this.version});

  final RealtimeChannel? channel;
  final AppVersion? version;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    final RealtimeChannel? resolvedChannel =
        channel ?? (Injection.isRegistered<RealtimeChannel>() ? Injection.get<RealtimeChannel>() : null);
    final String versionText =
        version?.display ??
        (Injection.isRegistered<AppVersion>() ? Injection.get<AppVersion>().display : AppVersion.fallback);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('连接与更新', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            if (resolvedChannel != null)
              RealtimeStatusSection(channel: resolvedChannel)
            else
              _hintRow(context, Icons.cloud_off_outlined, '遥控通道：未接入', scheme),
            const Divider(height: 22),
            ValueListenableBuilder<AppUpdateState>(
              valueListenable: AppUpdateController.instance,
              builder: (BuildContext context, AppUpdateState update, Widget? _) {
                final bool hasUpdate = update.result?.hasUpdate ?? false;
                final String latest = update.result?.latest?.version ?? '';
                final String status = switch (update.phase) {
                  AppUpdatePhase.checking => '正在检查更新…',
                  AppUpdatePhase.downloading => '正在后台下载 v$latest（${((update.progress ?? 0) * 100).round()}%）',
                  AppUpdatePhase.ready || AppUpdatePhase.installing => '新版本 v$latest 已就绪，点「更新」安装',
                  _ => hasUpdate ? '发现新版本 v$latest，点「更新」下载' : '已是最新版本',
                };
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _hintRow(context, Icons.info_outline, '$versionText · $status', scheme),
                    const SizedBox(height: 10),
                    if (hasUpdate)
                      FilledButton.tonalIcon(
                        onPressed: () => unawaited(handleUpdatePillTap(context, update)),
                        icon: const Icon(Icons.system_update_rounded, size: 18),
                        label: Text(update.phase == AppUpdatePhase.failed ? '重试' : '更新'),
                      )
                    else
                      OutlinedButton.icon(
                        onPressed: update.phase == AppUpdatePhase.checking
                            ? null
                            : () => unawaited(AppUpdateController.instance.check(manual: true)),
                        icon: const Icon(Icons.sync_rounded, size: 18),
                        label: Text(update.phase == AppUpdatePhase.checking ? '检查中…' : '检查更新'),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _hintRow(BuildContext context, IconData icon, String text, ColorScheme scheme) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 16, color: scheme.outline),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.outline)),
        ),
      ],
    );
  }
}
