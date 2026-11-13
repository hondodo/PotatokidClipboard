import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pscreen_home/core/server/account_session.dart';
import 'package:pscreen_home/features/parental/data/parental_admin_api.dart';
import 'package:pscreen_home/features/parental/domain/parental_config.dart';
import 'package:pscreen_home/features/parental/presentation/parental_common.dart';
import 'package:pscreen_home/features/parental/presentation/parental_subpages.dart';
import 'package:pscreen_screen/core/network/realtime_channel.dart';

/// Tab 一：今天（孩子驱动首页）。
///
/// 聚合「家庭概览 + 孩子状态 + 待处理解锁 + 今日记录」，让首屏只回答两件事：
/// 孩子今天看了多久、有没有事等我处理。所有派生数据（按孩子合并时长、当前
/// 观看者、待处理解锁数）在此纯函数计算，不耦合 `ParentalPage` 状态。
class ParentalTodayView extends StatelessWidget {
  const ParentalTodayView({
    super.key,
    required this.machines,
    required this.selected,
    required this.config,
    required this.watchEvents,
    required this.activeEvents,
    required this.unlockEvents,
    required this.unlockAckEvents,
    required this.sessions,
    required this.myAccount,
    required this.isAdmin,
    required this.actions,
    this.hasClaimedAccount = false,
    this.isServerError = false,
  });

  final List<ParentalMachine> machines;
  final ParentalMachine? selected;
  final ParentalConfig config;
  final List<RealtimeEvent> watchEvents;
  final List<RealtimeEvent> activeEvents;
  final List<RealtimeEvent> unlockEvents;
  final List<RealtimeEvent> unlockAckEvents;
  final List<ParentalSession> sessions;
  final String myAccount;
  final bool isAdmin;
  final ParentalActions actions;

  /// 本地是否已设置独立家长号（区别于设备派生号）；未设置时空态优先引导账号恢复。
  final bool hasClaimedAccount;

  /// 最近一次加载是否服务端报错；为 true 时不要直接显示「没有电视」，
  /// 而应先提示网络/服务异常（Phase 1：服务端不可达 ≠ 无设备）。
  final bool isServerError;

  /// 跨全部电视合并「今日」按档案分账的时长（秒）。
  Map<String, int> _mergedDailyByChild() {
    final String today = _dateKey(DateTime.now());
    final Map<String, int> result = <String, int>{};
    for (final RealtimeEvent event in watchEvents) {
      if ('${event.data['date'] ?? ''}' != today) continue;
      final dynamic raw = event.data['dailySecByChild'];
      if (raw is! Map) continue;
      raw.forEach((dynamic key, dynamic value) {
        if (value is num && value >= 0) {
          result['$key'] = (result['$key'] ?? 0) + value.toInt();
        }
      });
    }
    return result;
  }

  /// 跨全部电视合并当前观看的孩子（取新鲜上报里最新一条 childIds）。
  ///
  /// 关键点：
  /// 1. TV 退出儿童模式后会主动上报 `childIds: []` 表达「无人在看」，
  ///    必须尊重这条空上报，不能回落到配置预选（否则会一直显示某孩子在看）。
  /// 2. `parental_watch` 心跳周期 25s，超过新鲜窗口（90s）的上报不再代表
  ///    「正在看」——电视可能已离线或停止上报，避免陈旧状态长期滞留。
  List<String> _mergedActiveIds() {
    const Duration freshWindow = Duration(seconds: 90);
    final DateTime now = DateTime.now();
    int latestTs = -1;
    List<String>? freshIds;
    bool everSawChildIds = false;
    for (final RealtimeEvent event in <RealtimeEvent>[...watchEvents, ...activeEvents]) {
      final dynamic raw = event.data['childIds'];
      if (raw is! List) continue;
      everSawChildIds = true;
      if (event.ts <= 0) continue;
      // 过期上报不计入「正在看」。
      if (now.difference(DateTime.fromMillisecondsSinceEpoch(event.ts)) > freshWindow) {
        continue;
      }
      if (event.ts < latestTs) continue;
      latestTs = event.ts;
      freshIds = raw.map((dynamic item) => '$item').where((String item) => item.isNotEmpty).toList(growable: false);
    }
    // 从未收到任何 childIds 上报：冷启动兜底，回落配置预选。
    // 一旦收到过上报（含空列表 / 过期），即以实时为准——空 = 无人在看。
    if (!everSawChildIds) return config.activeChildIds;
    return freshIds ?? const <String>[];
  }

  /// 待处理解锁请求数（未回执且短码未过期），跨全部电视。
  int _pendingUnlockCount() {
    if (unlockEvents.isEmpty) return 0;
    final Set<String> acked = <String>{};
    for (final RealtimeEvent ack in unlockAckEvents) {
      final String code = '${ack.data['code'] ?? ''}'.trim();
      if (code.isNotEmpty) acked.add('${ack.from.trim()}|$code');
    }
    final DateTime now = DateTime.now();
    int count = 0;
    for (final RealtimeEvent event in unlockEvents) {
      final String code = '${event.data['code'] ?? ''}'.trim();
      if (code.isNotEmpty && acked.contains('${event.from.trim()}|$code')) continue;
      final bool expired =
          event.ts <= 0 || now.difference(DateTime.fromMillisecondsSinceEpoch(event.ts)) > const Duration(seconds: 60);
      if (!expired) count++;
    }
    return count;
  }

  static String _dateKey(DateTime time) =>
      '${time.year.toString().padLeft(4, '0')}-'
      '${time.month.toString().padLeft(2, '0')}-'
      '${time.day.toString().padLeft(2, '0')}';

  static String _formatDuration(int totalSec) {
    final int hours = totalSec ~/ 3600;
    final int minutes = (totalSec % 3600) ~/ 60;
    final int seconds = totalSec % 60;
    if (hours > 0) return '$hours 小时 $minutes 分';
    if (minutes > 0) return '$minutes 分 $seconds 秒';
    return '$seconds 秒';
  }

  static String _formatTime(int ms) {
    if (ms <= 0) return '—';
    final DateTime time = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(time.month)}-${two(time.day)} ${two(time.hour)}:${two(time.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    if (machines.isEmpty) {
      // 服务端不可达：先提示异常，绝不把「连不上」误报成「没有电视」（Phase 1）。
      if (isServerError) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.cloud_off_outlined, size: 40),
                const SizedBox(height: 12),
                Text('暂时无法连接服务', style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  '不是没有电视，而是家长端连不上服务端。请检查网络后点右上角刷新。',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
                ),
              ],
            ),
          ),
        );
      }
      // 无设备空态：同时提供「登录已有家长号」与「添加电视」两条路；
      // 重装/换手机的用户优先走账号恢复，而不是被引导去重新绑电视。
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
        children: <Widget>[
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Icon(Icons.tv_off_outlined, size: 20, color: scheme.primary),
                      const SizedBox(width: 8),
                      Text('还没有绑定电视', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    hasClaimedAccount
                        ? '这台手机已登录家长号。去「电视」页扫码添加电视，或登录另一个家长号查看其电视。'
                        : '如果是重装或换了手机，先用「家长号 + 口令」登录找回原电视与档案；'
                            '新用户可直接添加电视或创建家长号。',
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    icon: const Icon(Icons.login),
                    label: const Text('登录已有家长号'),
                    onPressed: () => unawaited(actions.openLoginExisting()),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.qr_code_scanner, size: 18),
                    label: const Text('扫码添加电视'),
                    onPressed: () => unawaited(actions.openDeviceManager()),
                  ),
                  if (!hasClaimedAccount) ...<Widget>[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.add_circle_outline),
                      label: const Text('创建新家长号'),
                      onPressed: () => unawaited(actions.openCreateAccount()),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '账号恢复：凭家长号 + 自设口令即可在任意设备找回同一批电视与儿童档案，'
            '无需重新绑定。',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
          ),
        ],
      );
    }
    final Map<String, int> daily = _mergedDailyByChild();
    final List<String> activeIds = _mergedActiveIds();
    final int pending = _pendingUnlockCount();
    final List<ParentalChild> children = config.children;
    final int onlineCount = machines.where((ParentalMachine m) => m.online).length;

    return RefreshIndicator(
      onRefresh: () => actions.reload(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: <Widget>[
          if (isAdmin)
            Card(
              margin: EdgeInsets.zero,
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.visibility_outlined, size: 18, color: scheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '只读代管：你以管理员身份查看全部电视与档案，但不能修改配置'
                        '（批准解锁请求除外）。',
                        style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (isAdmin) const SizedBox(height: 12),
          // 家庭概览（对齐交互原型：默认「全部电视」聚合视角，不被单台下拉驱动）
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('家庭视图', style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline)),
                    Text(
                      '全部电视 · $onlineCount/${machines.length} 台在线',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              if (AccountSession.isParent)
                FilledButton.tonal(
                  style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                  onPressed: () => unawaited(actions.openDeviceManager()),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[Icon(Icons.tv_outlined, size: 16), SizedBox(width: 4), Text('管理')],
                  ),
                ),
            ],
          ),
          // const SizedBox(height: 14),
          // // 跟apptitle重复了
          // const Text('今天', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          // 待处理解锁请求
          if (pending > 0)
            Card(
              margin: EdgeInsets.zero,
              color: scheme.errorContainer.withValues(alpha: 0.5),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                child: Row(
                  children: <Widget>[
                    Expanded(child: Text('$pending 条解锁请求待处理', style: theme.textTheme.bodyMedium)),
                    FilledButton(
                      style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                      onPressed: () => unawaited(
                        actions.push(
                          ParentalUnlockPage(
                            events: unlockEvents,
                            onUnlock: actions.unlock,
                            machine: selected,
                            acks: unlockAckEvents,
                            isAdmin: isAdmin,
                            myAccount: myAccount,
                            onManageDevices: AccountSession.isParent
                                ? () => unawaited(actions.openDeviceManager())
                                : null,
                          ),
                        ),
                      ),
                      child: const Text('去处理'),
                    ),
                  ],
                ),
              ),
            )
          else
            Card(
              margin: EdgeInsets.zero,
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
              child: const Padding(padding: EdgeInsets.all(12), child: Text('暂时没有待处理的解锁请求。')),
            ),
          const SizedBox(height: 12),
          // 孩子状态卡
          if (children.isEmpty)
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('尚未添加儿童档案，点下方「孩子」标签添加孩子并设置限额。', style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 8),
                    Text(
                      '想先遥控电视？到下方「电视」页，每台电视右侧都有遥控按钮。',
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
                    ),
                  ],
                ),
              ),
            )
          else
              for (final ParentalChild child in children)
              ChildStatusCard(
                child: child,
                usedMin: (daily[child.id] ?? 0) ~/ 60,
                limitMin: child.dailyLimitMin ?? 0,
                watching: activeIds.contains(child.id),
                actions: actions,
                readOnly: isAdmin,
              ),
          const SizedBox(height: 18),
          // 今日记录（已按孩子合并，跨设备）
          Row(
            children: <Widget>[
              Text('今日记录 · 已按孩子合并', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              const Spacer(),
              if (sessions.isNotEmpty)
                TextButton(
                  onPressed: () => unawaited(
                    actions.push(
                      ParentalWatchPage(
                        config: config,
                        machine: selected,
                        watchEvents: watchEvents,
                        activeEvents: activeEvents,
                        sessions: sessions,
                      ),
                    ),
                  ),
                  child: const Text('查看全部 ›'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          _TodaySessionsCard(sessions: sessions, scheme: scheme, theme: theme),
        ],
      ),
    );
  }
}

/// 今日记录（跨设备会话），纯展示。
class _TodaySessionsCard extends StatelessWidget {
  const _TodaySessionsCard({required this.sessions, required this.scheme, required this.theme});

  final List<ParentalSession> sessions;
  final ColorScheme scheme;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    if (sessions.isEmpty) {
      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('今日还没有观看会话记录。', style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline)),
        ),
      );
    }
    return Column(
      children: <Widget>[
        for (final ParentalSession session in sessions.take(20))
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.play_circle_outline),
              title: Text(
                '${session.childName} · ${session.machineName}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${ParentalTodayView._formatTime(session.startMs)} - '
                '${ParentalTodayView._formatTime(session.endMs)}'
                ' · 当日累计 ${ParentalTodayView._formatDuration(session.dailySec)}',
              ),
              trailing: Text(
                ParentalTodayView._formatDuration(session.durationSec),
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ),
      ],
    );
  }
}

/// 单个孩子状态卡（对齐交互原型）。
///
/// 第一行：头像 + 名字 + 状态胶囊，右侧 54px 时长环；
/// 第二行：今日已看 / 限额 + 线性进度条；
/// 底部：暂停 / 加时 / 改规则（孩子级操作；遥控属设备级，收在「电视」页）。
class ChildStatusCard extends StatelessWidget {
  const ChildStatusCard({
    super.key,
    required this.child,
    required this.usedMin,
    required this.limitMin,
    required this.watching,
    required this.actions,
    this.readOnly = false,
  });

  final ParentalChild child;
  final int usedMin;
  final int limitMin;
  final bool watching;
  final ParentalActions actions;

  /// 只读代管（admin）：禁用暂停/加时/改规则等写操作（D-03 客户端口径）。
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final double pct = limitMin > 0 ? (usedMin / limitMin).clamp(0.0, 1.0) : 0.0;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // 第一行：头像 + 名字 + 状态胶囊，右侧时长环。
            Row(
              children: <Widget>[
                CircleAvatar(child: Text(child.name.isNotEmpty ? child.name[0] : '?')),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(child.name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Row(
                        children: <Widget>[
                          Chip(
                            visualDensity: VisualDensity.compact,
                            label: Text(child.locked ? '已暂停' : (watching ? '正在看' : '空闲')),
                            backgroundColor:
                                (watching && !child.locked ? scheme.primaryContainer : scheme.surfaceContainerHighest)
                                    .withValues(alpha: 0.6),
                          ),
                          if (child.locked)
                            const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.lock, size: 15)),
                          if (child.readOnly)
                            Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: Chip(
                                visualDensity: VisualDensity.compact,
                                label: const Text('引用 · 只读'),
                                backgroundColor: scheme.secondaryContainer.withValues(alpha: 0.6),
                              ),
                            ),
                        ],
                      ),
                      if (child.readOnly && child.sourceLabel != null)
                        Text(
                          '来自 ${child.sourceLabel}',
                          style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
                        ),
                    ],
                  ),
                ),
                MinutesRing(pct: pct, label: '${(pct * 100).round()}%'),
              ],
            ),
            // 第二行：今日已看 / 限额 + 线性进度条。
            const SizedBox(height: 10),
            Text('今日已看 $usedMin / ${limitMin == 0 ? '不限' : '$limitMin 分钟'}', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 6,
                backgroundColor: scheme.surfaceContainerHighest,
                color: scheme.primary,
              ),
            ),
            // 底部：孩子级快捷动作（暂停/加时/改规则，对齐设计稿的 3 按钮）。
            // 引用档案在主本维护，本台只读：隐藏全部写入口，只给可操作指引。
            // admin 只读代管：同样禁用这些写操作，只给指引（D-03 客户端口径）。
            // 遥控是设备级操作，统一放在「电视」页每台电视行，不依赖孩子档案。
            const SizedBox(height: 12),
            if (child.readOnly)
              Text(
                '这份档案由主本维护；暂停、加时、改规则请到 ${child.sourceLabel ?? '主本电视'} 操作。',
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
              )
            else if (readOnly)
              Text(
                '只读代管：暂停、加时、改规则需由绑定该电视的家长操作。',
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  FilledButton.tonal(
                    style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                    onPressed: () => actions.toggleChildLock(child),
                    child: Text(child.locked ? '恢复观看' : '暂停'),
                  ),
                  FilledButton.tonal(
                    style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                    onPressed: () => actions.addChildExtra(child),
                    child: const Text('加时 15 分钟'),
                  ),
                  FilledButton.tonal(
                    style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                    onPressed: () => actions.editChild(child),
                    child: const Text('改规则 ›'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// 今日页的孩子时长环。
class MinutesRing extends StatelessWidget {
  const MinutesRing({super.key, required this.pct, required this.label});

  final double pct;
  final String label;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 54,
      height: 54,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          CircularProgressIndicator(value: pct, strokeWidth: 6, backgroundColor: scheme.surfaceContainerHighest),
          Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
