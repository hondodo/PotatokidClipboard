import 'package:flutter/material.dart';
import 'package:pscreen_home/features/parental/data/parental_admin_api.dart';
import 'package:pscreen_home/features/parental/domain/parental_config.dart';
import 'package:pscreen_home/features/parental/presentation/child_profile_editor.dart';
import 'package:pscreen_screen/core/network/realtime_channel.dart';

/// 模块① 儿童档案：总开关 + 档案列表（增删改，按档位显隐字段在编辑器内）。
class ChildrenSection extends StatelessWidget {
  const ChildrenSection({
    super.key,
    required this.config,
    required this.onSave,
  });

  final ParentalConfig config;

  /// 保存整份 parental 配置（页面负责调用服务端并给出结果提示）。
  final Future<void> Function(ParentalConfig next) onSave;

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
  });

  final ParentalChild child;
  final Future<void> Function() onEdit;
  final Future<void> Function() onDelete;

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
  });

  /// 按时间降序的解锁请求历史。
  final List<RealtimeEvent> events;

  final Future<void> Function(RealtimeEvent event) onUnlock;

  static const Duration _codeTtl = Duration(seconds: 60);

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
    if (events.isEmpty) {
      return Center(
        child: Text(
          '暂无解锁请求记录',
          style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
        ),
      );
    }
    final DateTime now = DateTime.now();
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: events.length,
      itemBuilder: (BuildContext context, int index) {
        final RealtimeEvent event = events[events.length - 1 - index];
        final String code = '${event.data['code'] ?? ''}'.trim();
        final String reason = '${event.data['reason'] ?? ''}'.trim();
        final DateTime ts = DateTime.fromMillisecondsSinceEpoch(event.ts);
        final bool expired = event.ts <= 0 || now.difference(ts) > _codeTtl;
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
                      Text(
                        code.isEmpty ? '（无短码）' : '短码 $code',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (event.from.isNotEmpty) '来源 ${event.from}',
                          if (reason.isNotEmpty) reason,
                          _timeOf(event.ts),
                        ].join(' · '),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (expired)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Text(
                      '已过期',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.outline,
                      ),
                    ),
                  )
                else
                  FilledButton.tonal(
                    onPressed: () => onUnlock(event),
                    child: const Text('解锁'),
                  ),
              ],
            ),
          ),
        );
      },
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
