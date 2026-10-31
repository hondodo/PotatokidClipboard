import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pscreen_home/core/di/injection.dart';
import 'package:pscreen_home/features/remote_control/data/thread_targets_store.dart';
import 'package:pscreen_home/features/remote_control/presentation/chat_page.dart';
import 'package:pscreen_home/features/remote_control/presentation/widgets/playback_badge.dart';
import 'package:pscreen_screen/core/network/realtime_channel.dart';

/// 遥控会话列表：显示通过「+」添加的目标设备（按登录账号云端同步）。
///
/// 第一行：备注名（未改名显示原始账号）；改名后第二行小字灰色显示原始账号；
/// 最后一行是设备类型 · 在线状态 · 当前场景。
/// 长按弹「重命名 / 移除」菜单。
///
/// 在线状态来自实时通道的 presence/roster，设备类型来自 state/roster 上报。
class ConversationListPage extends StatefulWidget {
  const ConversationListPage({super.key});

  @override
  State<ConversationListPage> createState() => _ConversationListPageState();
}

class _ConversationListPageState extends State<ConversationListPage> {
  RealtimeChannel get _channel => Injection.get<RealtimeChannel>();

  StreamSubscription<void>? _storeSub;
  StreamSubscription<RealtimePresence>? _presenceSub;
  StreamSubscription<RealtimeDeviceState>? _deviceSub;
  List<ThreadTarget> _targets = const <ThreadTarget>[];

  /// 本页已 watch 的设备：服务端只向 watcher 转发 state 帧，
  /// 列表要实时刷新音量/播放状态就必须保持订阅。
  final Set<String> _watching = <String>{};

  @override
  void initState() {
    super.initState();
    _targets = ThreadTargetsStore.instance.targets;
    _syncWatch();
    _storeSub = ThreadTargetsStore.instance.changes.listen((_) {
      if (!mounted) return;
      setState(() => _targets = ThreadTargetsStore.instance.targets);
      _syncWatch();
    });
    // 打开会话页：拉取云端列表（服务端时间戳 LWW，云端更新则覆盖本机）。
    unawaited(ThreadTargetsStore.instance.syncFromServer());
    _presenceSub = _channel.presence.listen((_) {
      if (mounted) setState(() {});
    });
    _deviceSub = _channel.deviceStates.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    for (final String account in _watching) {
      _channel.unwatch(account);
    }
    _watching.clear();
    _storeSub?.cancel();
    _presenceSub?.cancel();
    _deviceSub?.cancel();
    super.dispose();
  }

  /// 让订阅与当前列表保持一致：新增的补 watch，移除的退 watch。
  ///
  /// watch/unwatch 在通道内按账号引用计数，详情页遥控面板的
  /// 订阅互不影响。
  void _syncWatch() {
    final Set<String> next = _targets
        .map((ThreadTarget target) => target.account.trim())
        .where((String account) => account.isNotEmpty)
        .toSet();
    for (final String account in next.difference(_watching)) {
      _channel.watch(account);
    }
    for (final String account in _watching.difference(next)) {
      _channel.unwatch(account);
    }
    _watching
      ..clear()
      ..addAll(next);
  }

  @override
  Widget build(BuildContext context) {
    if (_targets.isEmpty) {
      return const Center(child: Text('还没有添加设备\n点右上角 + 手动输入或扫码添加', textAlign: TextAlign.center));
    }
    return ListView.separated(
      itemCount: _targets.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (BuildContext context, int index) {
        final ThreadTarget target = _targets[index];
        final String account = target.account;
        final RealtimeDeviceState? device = _channel.deviceInfoOf(account);
        final bool online = _channel.isOnline(account);
        final bool renamed = target.alias.isNotEmpty;
        // 当前设备音量（0-100，被控端随 state 帧上报）。
        final int? volume = online ? device?.sceneVolume : null;
        // 播放状态只有直播场景才有意义（其它页面播放器已销毁）。
        final String playbackLabel = (online && device?.sceneKind == 'live') ? (device?.playbackLabel ?? '') : '';
        return ListTile(
          leading: _OnlineDot(online: online),
          title: Row(
            children: [
              Text(target.displayName),
              if (volume != null) ...[
                const SizedBox(width: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(Icons.volume_up_rounded, size: 18),
                    const SizedBox(width: 4),
                    Text('$volume'),
                  ],
                ),
              ],
              if (playbackLabel.isNotEmpty) ...<Widget>[
                const SizedBox(width: 8),
                PlaybackBadge(label: playbackLabel, state: device?.playbackState ?? ''),
              ],
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // 改名后第二行小字灰色显示原始账号，方便对照是哪台设备。
              if (renamed)
                Text(
                  account,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.outline),
                ),
              Row(children: [Text(_subtitleOf(device, online))]),
            ],
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ChatPage(account: account, title: target.displayName),
            ),
          ),
          onLongPress: () => _showMenu(context, target),
        );
      },
    );
  }

  /// 长按菜单：重命名 / 移除（只作用于本机列表，同步后其它设备跟随）。
  Future<void> _showMenu(BuildContext context, ThreadTarget target) async {
    final String? action = await showModalBottomSheet<String>(
      context: context,
      builder: (BuildContext context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('重命名'),
              onTap: () => Navigator.of(context).pop('rename'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('移除'),
              onTap: () => Navigator.of(context).pop('remove'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    switch (action) {
      case 'rename':
        await _rename(context, target);
      case 'remove':
        await _remove(context, target);
      default:
        break;
    }
  }

  /// 重命名对话框：留空 = 恢复显示原始账号。
  Future<void> _rename(BuildContext context, ThreadTarget target) async {
    final String? alias = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => _RenameDialog(target: target),
    );
    if (alias == null) return;
    await ThreadTargetsStore.instance.rename(target.account, alias);
  }

  /// 移除该目标（只删本机列表，同步后其它设备跟随）。
  Future<void> _remove(BuildContext context, ThreadTarget target) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('移除设备'),
        content: Text('从会话列表移除 ${target.displayName}？'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('移除')),
        ],
      ),
    );
    if (confirm ?? false) {
      await ThreadTargetsStore.instance.remove(target.account);
    }
  }

  /// 第三行：设备类型 + 在线状态（+ 当前场景）。
  String _subtitleOf(RealtimeDeviceState? device, bool online) {
    final String kind = switch (device?.kind) {
      'home' => '中控屏',
      'tv' => '电视',
      null || '' => '未知设备',
      _ => '设备',
    };
    final String status = online ? '在线' : '离线';
    // 离线时场景是上一次上报的旧值，不展示，避免看起来仍在播放。
    final String scene = online ? (device?.scene['title']?.toString() ?? '') : '';
    return scene.isEmpty ? '$kind · $status' : '$kind · $status · $scene';
  }
}

/// 重命名输入对话框：controller 由本 State 持有并在 dispose 释放。
///
/// 不能在 showDialog future 完成后立即 dispose——弹窗退出动画期间
/// TextField 仍会引用 controller（曾因此崩溃）。
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.target});

  final ThreadTarget target;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.target.alias);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('重命名设备'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 20,
        decoration: InputDecoration(
          labelText: '备注名',
          hintText: widget.target.account,
          helperText: '留空则显示原始账号',
          counterText: '',
        ),
        onSubmitted: (String value) => Navigator.of(context).pop(value),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.of(context).pop(_controller.text), child: const Text('保存')),
      ],
    );
  }
}

/// 账号在线状态圆点：在线绿色，离线灰色。
class _OnlineDot extends StatelessWidget {
  const _OnlineDot({required this.online});

  final bool online;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: online ? const Color(0xFF34C759) : const Color(0xFFBDBDBD),
      ),
    );
  }
}
