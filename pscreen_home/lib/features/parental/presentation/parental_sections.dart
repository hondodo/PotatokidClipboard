import 'package:flutter/material.dart';
import 'package:pscreen_home/features/parental/data/parental_admin_api.dart';
import 'package:pscreen_home/features/parental/domain/parental_config.dart';
import 'package:pscreen_home/features/parental/presentation/child_profile_editor.dart';
import 'package:pscreen_home/features/parental/presentation/parental_quiz_editor.dart';
import 'package:pscreen_screen/core/network/realtime_channel.dart';

/// 模块① 儿童档案：总开关 + 档案列表（增删改，按档位显隐字段在编辑器内）。
class ChildrenSection extends StatelessWidget {
  const ChildrenSection({
    super.key,
    required this.config,
    required this.onSave,
    this.deviceId,
  });

  final ParentalConfig config;

  /// 保存整份 parental 配置（页面负责调用服务端并给出结果提示）。
  final Future<void> Function(ParentalConfig next) onSave;

  /// 当前选中的电视；为空时不显示「题库」入口（题库按设备 + 档案存储）。
  final String? deviceId;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: <Widget>[
        Card(
          margin: EdgeInsets.zero,
          child: SwitchListTile(
            title: const Text('儿童模式总开关'),
            subtitle: Text(
              config.enabled
                  ? '生效中：${config.children.length} 份档案的规则正在管控电视'
                  : '关闭（off）或没有档案时，电视端不启用任何管控',
            ),
            value: config.mode == 'on',
            onChanged: (bool value) =>
                onSave(config.copyWith(mode: value ? 'on' : 'off')),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Text(
              '儿童档案',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            FilledButton.tonalIcon(
              onPressed: () async {
                final ParentalChild? child = await ChildProfileEditorSheet.show(
                  context,
                );
                if (child == null) return;
                await onSave(
                  config.copyWith(
                    children: <ParentalChild>[...config.children, child],
                  ),
                );
              },
              icon: const Icon(Icons.add, size: 18),
              label: const Text('添加'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (config.children.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                '暂无档案：添加孩子后设置规则并打开总开关即可生效',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ),
          ),
        for (int i = 0; i < config.children.length; i++)
          _ChildCard(
            child: config.children[i],
            onQuiz: deviceId == null
                ? null
                : () => ParentalQuizEditorSheet.show(
                    context,
                    deviceId: deviceId!,
                    child: config.children[i],
                  ),
            onEdit: () async {
              final ParentalChild? next = await ChildProfileEditorSheet.show(
                context,
                initial: config.children[i],
              );
              if (next == null) return;
              final List<ParentalChild> children = List<ParentalChild>.of(
                config.children,
              );
              children[i] = next;
              await onSave(config.copyWith(children: children));
            },
            onDelete: () async {
              final bool? ok = await showDialog<bool>(
                context: context,
                builder: (BuildContext context) => AlertDialog(
                  title: Text('删除「${config.children[i].name}」？'),
                  content: const Text('删除后该档案的规则与限额一并移除。'),
                  actions: <Widget>[
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('取消'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('删除'),
                    ),
                  ],
                ),
              );
              if (ok != true) return;
              final List<ParentalChild> children = List<ParentalChild>.of(
                config.children,
              );
              children.removeAt(i);
              await onSave(config.copyWith(children: children));
            },
          ),
      ],
    );
  }
}

class _ChildCard extends StatelessWidget {
  const _ChildCard({
    required this.child,
    required this.onEdit,
    required this.onDelete,
    this.onQuiz,
  });

  final ParentalChild child;
  final Future<void> Function() onEdit;
  final Future<void> Function() onDelete;

  /// 答题解锁题库入口；未选中设备时不显示。
  final Future<void> Function()? onQuiz;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final List<String> details = <String>[
      if (child.age != null) '年龄 ${child.age}',
      '单次 ${child.sessionLimitMin == null ? '不限' : '${child.sessionLimitMin} 分钟'}',
      '单日 ${child.dailyLimitMin == null ? '不限' : '${child.dailyLimitMin} 分钟'}',
      if (child.quietHours.isNotEmpty) '禁看 ${child.quietHours.join('、')}',
      if (child.isStrict)
        '白名单分组 ${child.allowGroups.join('、')}${child.allowChannels.isEmpty ? '' : ' · 白名单频道 ${child.allowChannels.join('、')}'}'
      else if (child.hideGroups.isNotEmpty || child.hideChannels.isNotEmpty)
        '隐藏 ${[...child.hideGroups, ...child.hideChannels].join('、')}',
    ];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    child.name,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(child.profileModeLabel),
                  backgroundColor:
                      (child.isStrict
                              ? scheme.errorContainer
                              : scheme.secondaryContainer)
                          .withValues(alpha: 0.6),
                ),
                if (child.locked)
                  const Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Icon(Icons.lock, size: 16),
                  ),
                if (onQuiz != null)
                  IconButton(
                    tooltip: '题库（答题解锁）',
                    icon: const Icon(Icons.quiz_outlined, size: 20),
                    onPressed: () => onQuiz?.call(),
                  ),
                IconButton(
                  tooltip: '编辑',
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  onPressed: onEdit,
                ),
                IconButton(
                  tooltip: '删除',
                  icon: Icon(
                    Icons.delete_outline,
                    size: 20,
                    color: scheme.error,
                  ),
                  onPressed: onDelete,
                ),
              ],
            ),
            if (details.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  details.join(' · '),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 模块② 当前观看者：最新上报的 `activeChildIds` + 分档案当日时长
///（来自 `parental_watch` 分账载荷 `{childIds, sessionSecByChild, dailySecByChild, date}`）。
class WatchSection extends StatelessWidget {
  const WatchSection({
    super.key,
    required this.config,
    required this.machine,
    required this.watchEvents,
    required this.activeEvents,
    this.sessions = const <ParentalSession>[],
  });

  final ParentalConfig config;

  /// 当前选中的电视；设备列表尚未加载时为 null（按无数据展示）。
  final ParentalMachine? machine;

  /// 全部 `parental_watch` 历史（可能来自多台电视，按时间升序）。
  final List<RealtimeEvent> watchEvents;

  /// 全部 `parental_child_active` 历史（可能来自多台电视，按时间升序）。
  final List<RealtimeEvent> activeEvents;

  /// 服务端还原的会话级记录（跨设备）。
  final List<ParentalSession> sessions;

  /// 事件是否来自当前选中设备：`from` 是 TV 的通信账号（commAccount），
  /// 少数旧记录用设备 id，两者都认，避免过滤后整块空白。
  bool _fromSelected(RealtimeEvent event) {
    final ParentalMachine? selected = machine;
    if (selected == null) return false;
    final String comm = selected.commAccount;
    final String id = selected.id;
    return (comm.isNotEmpty && event.from == comm) ||
        (id.isNotEmpty && event.from == id);
  }

  List<RealtimeEvent> _watchForSelected() =>
      watchEvents.where(_fromSelected).toList(growable: false);

  List<RealtimeEvent> _activeForSelected() =>
      activeEvents.where(_fromSelected).toList(growable: false);

  /// 当前选中设备的最新 `childIds`；空列表 = 明确「无人在看」。
  /// 该设备没有任何上报时才回落到配置默认预选。
  List<String> _activeIds(
    List<RealtimeEvent> watch,
    List<RealtimeEvent> active,
  ) {
    final List<RealtimeEvent> merged = <RealtimeEvent>[...watch, ...active]
      ..sort((RealtimeEvent a, RealtimeEvent b) => b.ts.compareTo(a.ts));
    for (final RealtimeEvent event in merged) {
      final dynamic raw = event.data['childIds'];
      if (raw is List) {
        return raw
            .map((dynamic item) => '${item ?? ''}')
            .where((String item) => item.isNotEmpty)
            .toList(growable: false);
      }
    }
    return config.activeChildIds;
  }

  /// 最新一份「今天」的分账时长（只算当前选中设备，按 childId 取各自
  /// 最新；不做跨设备求和——多设备合计需产品确认后另行实现）。
  Map<String, int> _todayDailySec(List<RealtimeEvent> watch) {
    final String today = _dateKey(DateTime.now());
    final Map<String, int> result = <String, int>{};
    for (final RealtimeEvent event in watch) {
      if ('${event.data['date'] ?? ''}' != today) continue;
      final dynamic raw = event.data['dailySecByChild'];
      if (raw is! Map) continue;
      raw.forEach((dynamic key, dynamic value) {
        if (value is num && value >= 0) {
          // watch 按 ts 升序，后写即覆盖为该 childId 的最新值。
          result['$key'] = value.toInt();
        }
      });
    }
    return result;
  }

  /// 当前选中设备最后一条 `parental_watch`（不按日期过滤，用于展示延迟）。
  RealtimeEvent? _lastWatch(List<RealtimeEvent> watch) {
    RealtimeEvent? latest;
    for (final RealtimeEvent event in watch) {
      if (latest == null || event.ts > latest.ts) latest = event;
    }
    return latest;
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
    return '${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}';
  }

  /// 相对时间：用服务端 `ts`（`Date.now()`）与中控本地时钟比较，
  /// 仅用于「x 分钟前」的粗略感知，不参与「今日」判定。
  static String _formatAgo(int ms, DateTime now) {
    if (ms <= 0) return '';
    final int minutes = now
        .difference(DateTime.fromMillisecondsSinceEpoch(ms))
        .inMinutes;
    if (minutes <= 0) return '刚刚';
    if (minutes < 60) return '$minutes 分钟前';
    final int hours = minutes ~/ 60;
    if (hours < 24) return '$hours 小时前';
    return '${hours ~/ 24} 天前';
  }

  String _nameOf(String childId) {
    for (final ParentalChild child in config.children) {
      if (child.id == childId) return child.name;
    }
    return childId;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final List<RealtimeEvent> watch = _watchForSelected();
    final List<RealtimeEvent> active = _activeForSelected();
    final List<String> activeIds = _activeIds(watch, active);
    final Map<String, int> daily = _todayDailySec(watch);
    final RealtimeEvent? lastWatch = _lastWatch(watch);
    final DateTime now = DateTime.now();

    if (watch.isEmpty && active.isEmpty && sessions.isEmpty) {
      return Center(
        child: Text(
          machine == null ? '请先选择设备' : '暂无观看上报（电视端心跳附带 parental_watch 后展示）',
          style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
        ),
      );
    }

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
                Text(
                  '当前观看者',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                if (activeIds.isEmpty)
                  Text('未上报在看孩子', style: theme.textTheme.bodyMedium)
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: activeIds
                        .map(
                          (String id) => Chip(
                            visualDensity: VisualDensity.compact,
                            avatar: const Icon(Icons.person, size: 16),
                            label: Text(_nameOf(id)),
                          ),
                        )
                        .toList(growable: false),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '今日时长（按档案分账）',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          lastWatch == null
              ? '暂无上报记录'
              : '最后上报 ${_formatTime(lastWatch.ts)}'
                    '（${_formatAgo(lastWatch.ts, now)}，服务器时间）',
          style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
        ),
        const SizedBox(height: 8),
        if (config.children.isEmpty)
          Text(
            '暂无档案，无法按时长对账',
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
          )
        else
          for (final ParentalChild child in config.children)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                dense: true,
                leading: Icon(
                  activeIds.contains(child.id)
                      ? Icons.visibility
                      : Icons.person_outline,
                  color: activeIds.contains(child.id) ? scheme.primary : null,
                ),
                title: Text(child.name),
                subtitle: child.dailyLimitMin == null
                    ? null
                    : Text('单日限额 ${child.dailyLimitMin} 分钟'),
                trailing: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Text(
                      daily.containsKey(child.id)
                          ? _formatDuration(daily[child.id]!)
                          : '今日未上报',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (!daily.containsKey(child.id) && lastWatch != null)
                      Text(
                        '最后 ${_formatTime(lastWatch.ts)}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.outline,
                        ),
                      ),
                  ],
                ),
              ),
            ),
        if (sessions.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            '观看会话',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
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
                  '${_formatTime(session.startMs)} - ${_formatTime(session.endMs)}'
                  ' · 当日累计 ${_formatDuration(session.dailySec)}',
                ),
                trailing: Text(
                  _formatDuration(session.durationSec),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

/// 模块③ 解锁请求记录：历史 `parental_unlock_request`，短码未过期的可点
/// 「解锁」补发 `parental_unlock`（60s 过期语义由电视端校验）。
class UnlockSection extends StatelessWidget {
  const UnlockSection({
    super.key,
    required this.events,
    required this.onUnlock,
    this.machine,
    this.acks = const <RealtimeEvent>[],
    this.isAdmin = false,
    this.myAccount = '',
    this.onManageDevices,
  });

  /// 按时间降序的解锁请求历史。
  final List<RealtimeEvent> events;

  final Future<void> Function(RealtimeEvent event) onUnlock;

  /// 当前选中的电视：请求 / 回执都只展示该电视的，避免多台电视混在一起。
  final ParentalMachine? machine;

  /// `parental_unlock_ack` 回执（按短码关联，展示谁解锁 / 结果）。
  final List<RealtimeEvent> acks;

  /// 管理员看全量并标注「代管」；家长只看自己绑定的电视。
  final bool isAdmin;

  /// 当前登录账号，用于判断选中电视是否由自己绑定（admin 未绑定时标代管）。
  final String myAccount;

  /// 未绑定该电视时的补绑入口（家长端打开绑定管理）。
  final VoidCallback? onManageDevices;

  static const Duration _codeTtl = Duration(seconds: 60);

  /// 事件来源是否属于当前选中的电视（`from` 可能是设备 id 或通信账号）。
  static bool _belongsTo(RealtimeEvent event, ParentalMachine? machine) {
    if (machine == null) return true;
    final String from = event.from.trim();
    if (from.isEmpty) return false;
    return from == machine.id || from == machine.commAccount;
  }

  /// 按「来源 + 短码」取最新回执。
  Map<String, Map<String, dynamic>> _ackByCode() {
    final Map<String, Map<String, dynamic>> latest = <String, Map<String, dynamic>>{};
    for (final RealtimeEvent ack in acks) {
      final String code = '${ack.data['code'] ?? ''}'.trim();
      if (code.isEmpty) continue;
      final String key = '${ack.from.trim()}|$code';
      final Map<String, dynamic>? current = latest[key];
      final int ts = (current?['_ts'] as num?)?.toInt() ?? -1;
      if (ack.ts <= ts) continue;
      latest[key] = <String, dynamic>{...ack.data, '_ts': ack.ts};
    }
    return latest;
  }

  static String _resultLabel(String result) => switch (result) {
    'ok' => '已解锁',
    'expired' => '短码已过期',
    'already-unlocked' => '无需解锁（已解锁）',
    'forbidden' => '无权限（未绑定该电视）',
    _ => result.isEmpty ? '未回执' : result,
  };

  static String _timeOf(int ts) {
    if (ts <= 0) return '';
    final DateTime time = DateTime.fromMillisecondsSinceEpoch(ts);
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(time.month)}-${two(time.day)} ${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final List<RealtimeEvent> visible = machine == null
        ? events
        : events
              .where((RealtimeEvent event) => _belongsTo(event, machine))
              .toList(growable: false);
    final Map<String, Map<String, dynamic>> ackByCode = _ackByCode();
    // 家长未绑定选中电视时，服务端会按「无权限」拒绝 parental_unlock；
    // 这里提前说明并给出补绑入口（admin 未绑定时仍可代管，不提示）。
    final bool unbound = !isAdmin &&
        machine != null &&
        myAccount.isNotEmpty &&
        !machine!.parents.contains(myAccount);
    final Widget? unboundCard = unbound
        ? Card(
            margin: const EdgeInsets.only(bottom: 8),
            color: scheme.errorContainer.withValues(alpha: 0.5),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              child: Row(
                children: <Widget>[
                  Icon(Icons.link_off, size: 18, color: scheme.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '当前账号 $myAccount 未绑定这台电视，服务端会把解锁命令按'
                      '「无权限」拒绝。请先补绑后再解锁。',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  if (onManageDevices != null)
                    TextButton(onPressed: onManageDevices, child: const Text('去绑定')),
                ],
              ),
            ),
          )
        : null;
    final Widget hint = Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
      child: ListTile(
        dense: true,
        leading: Icon(Icons.tips_and_updates_outlined, size: 20, color: scheme.primary),
        title: const Text('解锁方式在「设置」标签页切换'),
        subtitle: const Text(
          '可选远程确认 / PIN / 算术题 / 答题解锁；'
          '答题解锁需先在「档案」里给儿童维护题库，电视端会跳过填空题，'
          '题库为空或只有填空题时回退短码页。',
        ),
        trailing: TextButton(
          onPressed: () => DefaultTabController.of(context).animateTo(4),
          child: const Text('去设置'),
        ),
      ),
    );
    if (visible.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: <Widget>[
          ?unboundCard,
          hint,
          const SizedBox(height: 32),
          Center(
            child: Text(
              '暂无解锁请求记录',
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
            ),
          ),
        ],
      );
    }
    final DateTime now = DateTime.now();
    // 头部固定为「未绑定提示（可选）+ 解锁方式提示」，其余才是请求记录。
    final int headerCount = unboundCard == null ? 1 : 2;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: visible.length + headerCount,
      itemBuilder: (BuildContext context, int index) {
        if (index == 0 && unboundCard != null) return unboundCard;
        if (index == (unboundCard == null ? 0 : 1)) return hint;
        final RealtimeEvent event = visible[visible.length - (index - headerCount + 1)];
        final String code = '${event.data['code'] ?? ''}'.trim();
        final String reason = '${event.data['reason'] ?? ''}'.trim();
        final DateTime ts = DateTime.fromMillisecondsSinceEpoch(event.ts);
        final bool expired = event.ts <= 0 || now.difference(ts) > _codeTtl;
        final Map<String, dynamic>? ack =
            code.isEmpty ? null : ackByCode['${event.from.trim()}|$code'];
        final String result = '${ack?['result'] ?? ''}'.trim();
        final String actor = '${ack?['actor'] ?? ''}'.trim();
        final bool actingAsAdmin = isAdmin &&
            (machine != null && !machine!.parents.contains(myAccount));
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Text(
                            code.isEmpty ? '（无短码）' : '短码 $code',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (actingAsAdmin) ...<Widget>[
                            const SizedBox(width: 8),
                            _roleBadge(theme, '代管'),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (machine != null && machine!.name.isNotEmpty)
                            '电视 ${machine!.name}'
                          else if (event.from.isNotEmpty)
                            '来源 ${event.from}',
                          if (reason.isNotEmpty) reason,
                          _timeOf(event.ts),
                        ].join(' · '),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      if (ack != null) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(
                          '${actor.isEmpty ? (actingAsAdmin ? '管理员' : '家长') : actor}'
                          ' · ${_resultLabel(result)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: result == 'ok'
                                ? scheme.primary
                                : scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (ack == null && expired)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Text(
                      '已过期',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.outline,
                      ),
                    ),
                  )
                else if (ack == null)
                  FilledButton.tonal(
                    onPressed: () => onUnlock(event),
                    child: const Text('解锁'),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Text(
                      _resultLabel(result),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: result == 'ok' ? scheme.primary : scheme.outline,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 管理员视角：未绑定到该电视的请求标「代管」。
  static Widget _roleBadge(ThemeData theme, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onTertiaryContainer,
        ),
      ),
    );
  }
}

/// 模块④ 设置：`ownerAccount` / 解锁方式（remote|pin|arith）/ PIN。
class ParentalSettingsSection extends StatefulWidget {
  const ParentalSettingsSection({
    super.key,
    required this.config,
    required this.machine,
    required this.onSave,
  });

  final ParentalConfig config;
  final ParentalMachine? machine;
  final Future<void> Function(ParentalConfig next) onSave;

  @override
  State<ParentalSettingsSection> createState() =>
      _ParentalSettingsSectionState();
}

class _ParentalSettingsSectionState extends State<ParentalSettingsSection> {
  late final TextEditingController _owner;
  late final TextEditingController _pin;
  late String _unlockMode;

  static const Map<String, String> _modeLabels = <String, String>{
    'remote': '远程确认（手机弹层）',
    'pin': 'PIN 兜底',
    'arith': '算术题兜底',
    'quiz': '答题解锁（使用儿童题库）',
  };

  @override
  void initState() {
    super.initState();
    _owner = TextEditingController(text: widget.config.ownerAccount);
    _pin = TextEditingController(text: widget.config.pin);
    _unlockMode = _modeLabels.containsKey(widget.config.unlockMode)
        ? widget.config.unlockMode
        : 'remote';
  }

  @override
  void dispose() {
    _owner.dispose();
    _pin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String fallbackOwner = widget.machine?.owner ?? '';
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: <Widget>[
        TextField(
          controller: _owner,
          decoration: InputDecoration(
            labelText: '家长账号（ownerAccount）',
            helperText: fallbackOwner.isEmpty
                ? '解锁请求的投递目标；空 = 回落设备归属'
                : '解锁请求的投递目标；空 = 回落设备归属 $fallbackOwner',
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 16),
        Text('解锁方式', style: theme.textTheme.bodySmall),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: _modeLabels.entries
              .map(
                (MapEntry<String, String> entry) => ChoiceChip(
                  label: Text(entry.value),
                  selected: _unlockMode == entry.key,
                  onSelected: (_) => setState(() => _unlockMode = entry.key),
                ),
              )
              .toList(growable: false),
        ),
        if (_unlockMode == 'quiz')
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '答题模式只能用题库解锁；题库在「儿童档案」卡片里维护，'
              '多个孩子取年龄最大的一份，同岁合并。全部无题时电视回退短码页，'
              '请先添加选择题后再保存此模式。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
        const SizedBox(height: 12),
        if (_unlockMode == 'pin')
          TextField(
            controller: _pin,
            keyboardType: TextInputType.number,
            maxLength: 4,
            decoration: const InputDecoration(
              labelText: '解锁 PIN（4 位数字）',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () => widget.onSave(
            widget.config.copyWith(
              ownerAccount: _owner.text.trim(),
              unlockMode: _unlockMode,
              pin: _unlockMode == 'pin' ? _pin.text.trim() : widget.config.pin,
            ),
          ),
          child: const Text('保存设置'),
        ),
      ],
    );
  }
}
