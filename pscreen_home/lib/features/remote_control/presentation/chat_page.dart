import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:pscreen_home/core/di/injection.dart';
import 'package:pscreen_home/features/remote_control/core/control_config.dart';
import 'package:pscreen_home/features/remote_control/presentation/widgets/online_dot.dart';
import 'package:pscreen_home/features/remote_control/presentation/widgets/target_remote_panel.dart';
import 'package:pscreen_screen/core/network/realtime_channel.dart';

/// 会话页：合并「当前账号 + 管理员」与该设备的消息/事件时间线。
///
/// 样式对齐 realtime.html 的事件卡片：类型徽标、来源 → 目标、右侧时间，
/// 事件按字段展示标签 chips 与原因，并可展开原始 JSON。
class ChatPage extends StatefulWidget {
  const ChatPage({super.key, required this.account, required this.title});

  final String account;
  final String title;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  List<RealtimeThreadItem> _items = <RealtimeThreadItem>[];
  StreamSubscription<RealtimeMessage>? _msgSub;
  StreamSubscription<RealtimeEvent>? _eventSub;
  StreamSubscription<RealtimeConnectionState>? _stateSub;
  bool _loading = true;

  /// 轻提示：浮在时间线底部一行，2 秒后自动消失，不占布局也不挡面板。
  String? _hint;
  bool _hintError = false;
  Timer? _hintTimer;

  RealtimeChannel get _channel => Injection.get<RealtimeChannel>();

  /// 当前登录账号（连接握手账号，可能是设备号）。
  String get _me => _channel.account;

  bool get _isAdminSelf => _me == ControlConfig.adminAccount && widget.account == ControlConfig.adminAccount;

  @override
  void initState() {
    super.initState();
    _channel.markRead(widget.account);
    // 线程订阅：服务端立即回推合并快照，之后新帧实时推过来。
    unawaited(_loadThread());
    _msgSub = _channel.messages.listen(_handleMessage);
    _eventSub = _channel.events.listen(_handleEvent);
    // 重连后补拉一次快照，避免断线期间漏掉的往来。
    _stateSub = _channel.connectionState.listen((RealtimeConnectionState s) {
      if (s == RealtimeConnectionState.connected) unawaited(_loadThread());
    });
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    _msgSub?.cancel();
    _eventSub?.cancel();
    _stateSub?.cancel();
    _channel.unwatchThread(widget.account);
    super.dispose();
  }

  Future<void> _loadThread() async {
    final List<RealtimeThreadItem> items = await _channel.watchThread(
      widget.account,
      also: <String>[ControlConfig.adminAccount],
      limit: 100,
    );
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  /// 该帧是否属于本会话：peer 与「当前账号 或 管理员」的往来。
  bool _belongs(String from, String to) {
    final String peer = widget.account;
    if (from != peer && to != peer) return false;
    final String other = from == peer ? to : from;
    return other == _me || other == ControlConfig.adminAccount;
  }

  void _handleMessage(RealtimeMessage message) {
    if (message.body.isEmpty || !_belongs(message.from, message.to)) return;
    _merge(
      RealtimeThreadItem(
        kind: 'msg',
        id: message.id,
        from: message.from,
        to: message.to,
        text: message.body,
        ts: message.ts,
      ),
    );
  }

  void _handleEvent(RealtimeEvent event) {
    if (event.event.isEmpty || !_belongs(event.from, event.to)) return;
    _merge(
      RealtimeThreadItem(
        kind: 'event',
        id: event.id,
        from: event.from,
        to: event.to,
        event: event.event,
        data: Map<String, Object?>.from(event.data),
        ts: event.ts,
      ),
    );
  }

  /// 按 id 去重后按时间升序插入；本地乐观消息用 `local-` 前缀自增 id。
  void _merge(RealtimeThreadItem item) {
    if (!mounted) return;
    if (item.id.isNotEmpty && _items.any((RealtimeThreadItem existing) => existing.id == item.id)) {
      return;
    }
    final List<RealtimeThreadItem> next = <RealtimeThreadItem>[..._items];
    // 服务端回显与本地乐观消息合并：同发放同内容且时间接近，用服务端 id 替换本地项，
    // 避免「自己发给自己」等被直投回显的场景出现两条重复卡片。
    if (!item.id.startsWith('local-')) {
      final int localIndex = next.indexWhere(
        (RealtimeThreadItem existing) =>
            existing.id.startsWith('local-') &&
            existing.kind == item.kind &&
            existing.from == item.from &&
            existing.to == item.to &&
            existing.text == item.text &&
            (item.ts - existing.ts).abs() <= 15000,
      );
      if (localIndex >= 0) {
        next[localIndex] = item;
      } else {
        next.add(item);
      }
    } else {
      next.add(item);
    }
    next.sort((RealtimeThreadItem a, RealtimeThreadItem b) => a.ts.compareTo(b.ts));
    setState(() {
      _items = next.length > 300 ? next.sublist(next.length - 300) : next;
    });
  }

  /// 显示轻提示：不用 SnackBar，避免占一条底部横条并遮挡遥控面板。
  void _showHint(String message, {bool error = false}) {
    if (!mounted) return;
    _hintTimer?.cancel();
    setState(() {
      _hint = message;
      _hintError = error;
    });
    _hintTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _hint = null);
    });
  }

  Future<void> _send(String body) async {
    final String text = body.trim();
    if (text.isEmpty) return;
    if (_isAdminSelf) {
      _showHint('不能给自己发消息', error: true);
      return;
    }
    // 先插入本地乐观消息，再等服务端回显：服务端的 msg 帧与 ack 顺序不定，
    // 先插入可保证回显总能合并到本地项，避免出现两条重复卡片。
    final String localId = 'local-${DateTime.now().microsecondsSinceEpoch}';
    _merge(
      RealtimeThreadItem(
        kind: 'msg',
        id: localId,
        from: _me,
        to: widget.account,
        text: text,
        ts: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    final bool ok = await _channel.sendText(to: widget.account, body: text);
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _items = _items.where((RealtimeThreadItem item) => item.id != localId).toList(growable: false);
      });
    }
    _showHint(ok ? '已发送' : '发送失败', error: !ok);
  }

  /// 发送消息：底部弹窗输入，确认后发送。
  Future<void> _openSendSheet() async {
    final String? body = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (BuildContext context) => const _SendMessageSheet(),
    );
    if (body == null || body.trim().isEmpty) return;
    await _send(body);
  }

  @override
  Widget build(BuildContext context) {
    final RealtimeDeviceState? info = _channel.deviceInfoOf(widget.account);
    final String kind = info?.kind ?? '';
    final bool online = _channel.isOnline(widget.account);
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            OnlineDot(online: online),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.title),
                Row(
                  children: [
                    Text(switch (kind) {
                      'home' => '中控屏',
                      'tv' => '电视',
                      _ => '未知设备',
                    }, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
      body: Column(
        children: <Widget>[
          // 轻提示浮在时间线左下角，不占布局、不遮面板，2 秒自动淡出。
          Expanded(
            child: Stack(
              children: <Widget>[
                Positioned.fill(child: _buildTimeline()),
                Positioned(left: 16, bottom: 8, child: _buildHintPill()),
              ],
            ),
          ),
          // 遥控面板常驻底部（替换原输入行）：按钮行始终可见，
          // 频道列表与发送消息都走弹窗，避免小屏被内容撑爆。
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.5),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: TargetRemotePanel(
                account: widget.account,
                onCommand: _send,
                onSendMessage: _openSendSheet,
                onHint: _showHint,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHintPill() {
    final String? hint = _hint;
    if (hint == null) return const SizedBox.shrink();
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color color = _hintError ? scheme.error : scheme.primary;
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(_hintError ? Icons.error_outline : Icons.check_circle_outline, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              hint,
              style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeline() {
    if (_items.isEmpty) {
      return Center(child: Text(_loading ? '加载中…' : '暂无消息与事件'));
    }
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: _items.length,
      itemBuilder: (BuildContext context, int index) {
        return _ThreadCard(item: _items[_items.length - 1 - index], me: _me);
      },
    );
  }
}

/// 发送消息弹窗：输入后把文本返回给会话页，由会话页负责发送。
class _SendMessageSheet extends StatefulWidget {
  const _SendMessageSheet();

  @override
  State<_SendMessageSheet> createState() => _SendMessageSheetState();
}

class _SendMessageSheetState extends State<_SendMessageSheet> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final String text = _controller.text.trim();
    if (text.isEmpty) return;
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('发送消息', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              autofocus: true,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(hintText: '输入消息内容', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                TextButton(onPressed: () => Navigator.of(context).maybePop(), child: const Text('取消')),
                const SizedBox(width: 8),
                FilledButton(onPressed: _submit, child: const Text('发送')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 一条时间线卡片（消息或事件，样式参考 realtime.html）。
class _ThreadCard extends StatelessWidget {
  const _ThreadCard({required this.item, required this.me});

  final RealtimeThreadItem item;
  final String me;

  static const Color _msgColor = Color(0xFF4F8CFF);
  static const Color _cmdColor = Color(0xFFB18CFF);
  static const Color _channelColor = Color(0xFF39C6B0);
  static const Color _okColor = Color(0xFF34C759);
  static const Color _retryColor = Color(0xFFFFB020);
  static const Color _failColor = Color(0xFFFF5A5F);
  static const Color _sceneColor = Color(0xFF8E9BFF);

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool mine = item.from == me;
    final bool isEvent = item.isEvent;
    final bool isCommand = !isEvent && _looksLikeCommand(item.text);

    final Color cardColor = isEvent
        ? scheme.surfaceContainerHigh
        : mine
        ? scheme.primary.withValues(alpha: 0.14)
        : scheme.surfaceContainerHigh;

    final Widget card = Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              _Badge(
                label: _badgeLabel(isEvent: isEvent, isCommand: isCommand),
                color: _badgeColor(isEvent: isEvent, isCommand: isCommand),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${item.from} → ${item.to}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant, fontFamily: 'monospace'),
                ),
              ),
              const SizedBox(width: 8),
              Text(_time(item.ts), style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 8),
          if (isEvent) _EventBody(item: item) else _MessageBody(item: item, isCommand: isCommand),
        ],
      ),
    );

    return Align(
      alignment: isEvent ? Alignment.center : (mine ? Alignment.centerRight : Alignment.centerLeft),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: isEvent ? double.infinity : 640),
        child: card,
      ),
    );
  }

  static bool _looksLikeCommand(String text) => text.trimLeft().startsWith('{"t":"cmd"');

  String _badgeLabel({required bool isEvent, required bool isCommand}) {
    if (!isEvent) return isCommand ? '命令' : '消息';
    return switch (item.event) {
      'scene_changed' => '场景切换',
      'channel_changed' => '切换频道',
      'play_start' => '开始播放',
      'play_ok' => '播放正常',
      'play_retry' => '播放重试',
      'play_fail' => '播放失败',
      _ => item.event,
    };
  }

  Color _badgeColor({required bool isEvent, required bool isCommand}) {
    if (!isEvent) return isCommand ? _cmdColor : _msgColor;
    return switch (item.event) {
      'scene_changed' => _sceneColor,
      'channel_changed' => _channelColor,
      'play_start' => _msgColor,
      'play_ok' => _okColor,
      'play_retry' => _retryColor,
      'play_fail' => _failColor,
      _ => const Color(0xFF9AA4B2),
    };
  }

  static String _time(int ts) {
    if (ts <= 0) return '';
    final DateTime t = DateTime.fromMillisecondsSinceEpoch(ts);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }
}

/// 消息/命令正文。
class _MessageBody extends StatelessWidget {
  const _MessageBody({required this.item, required this.isCommand});

  final RealtimeThreadItem item;
  final bool isCommand;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    if (!isCommand) {
      return SelectableText(item.text, style: theme.textTheme.bodyMedium);
    }
    // 命令信封：只展示命令名与参数摘要，原始 JSON 可展开。
    Map<String, dynamic>? frame;
    try {
      final dynamic decoded = jsonDecode(item.text);
      if (decoded is Map<String, dynamic>) frame = decoded;
    } catch (_) {
      frame = null;
    }
    final String name = '${frame?['name'] ?? ''}';
    final dynamic args = frame?['args'];
    final String argsText = args is Map && args.isNotEmpty ? jsonEncode(args) : '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          name.isEmpty ? '命令' : '命令：$name',
          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        if (argsText.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(argsText, style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace')),
          ),
        _RawJson(source: item.text),
      ],
    );
  }
}

/// 事件正文：主信息 + 标签 chips + 原因 + 原始 JSON。
class _EventBody extends StatelessWidget {
  const _EventBody({required this.item});

  final RealtimeThreadItem item;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Map<String, Object?> data = item.data;
    final String title = _title(data);
    final List<String> chips = _chips(data);
    final String source = '${data['source'] ?? ''}';
    final String reason = '${data['reason'] ?? ''}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (title.isNotEmpty) Text(title, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
        if (chips.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(spacing: 6, runSpacing: 4, children: chips.map((String text) => _Chip(text: text)).toList()),
          ),
        if (source.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: SelectableText(
              source,
              maxLines: 2,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        if (reason.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('原因：$reason', style: theme.textTheme.bodySmall),
          ),
        _RawJson(source: jsonEncode(<String, Object?>{'event': item.event, 'data': data})),
      ],
    );
  }

  String _title(Map<String, Object?> data) {
    final String channel = '${data['channelName'] ?? ''}';
    if (channel.isNotEmpty) return '频道：$channel';
    final String title = '${data['title'] ?? ''}';
    if (title.isNotEmpty) return item.event == 'scene_changed' ? '场景：$title' : title;
    return '';
  }

  List<String> _chips(Map<String, Object?> data) {
    final List<String> chips = <String>[];
    final int sourceTotal = _intOf(data['sourceTotal']);
    if (sourceTotal > 0) {
      chips.add('源 ${_intOf(data['sourceIndex']) + 1}/$sourceTotal');
    }
    final int round = _intOf(data['round']);
    if (round > 0) chips.add('第 $round 轮');
    final int elapsedMs = _intOf(data['elapsedMs']);
    if (elapsedMs > 0) chips.add('耗时 ${(elapsedMs / 1000).toStringAsFixed(1)}s');
    final int channelIndex = _intOf(data['channelIndex']);
    if (channelIndex >= 0 && data.containsKey('channelIndex')) chips.add('序号 ${channelIndex + 1}');
    if (data['viaProxy'] == true) chips.add('代理');
    return chips;
  }

  static int _intOf(Object? value) => value is num ? value.toInt() : int.tryParse('${value ?? ''}') ?? 0;
}

/// 类型徽标。
class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(4)),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}

/// 字段标签（源 1/1、第 1 轮、耗时 0.7s…）。
class _Chip extends StatelessWidget {
  const _Chip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
    );
  }
}

/// 可展开的原始 JSON（默认收起）。
class _RawJson extends StatefulWidget {
  const _RawJson({required this.source});

  final String source;

  @override
  State<_RawJson> createState() => _RawJsonState();
}

class _RawJsonState extends State<_RawJson> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String pretty = _pretty(widget.source);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  _open ? Icons.expand_more : Icons.chevron_right,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                Text('原始 JSON', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ),
        if (_open)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(6),
            ),
            child: SelectableText(pretty, style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
          ),
      ],
    );
  }

  static String _pretty(String source) {
    try {
      return const JsonEncoder.withIndent('  ').convert(jsonDecode(source));
    } catch (_) {
      return source;
    }
  }
}
