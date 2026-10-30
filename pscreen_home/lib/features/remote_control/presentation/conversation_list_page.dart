import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pscreen_home/core/di/injection.dart';
import 'package:pscreen_home/features/remote_control/data/thread_targets_store.dart';
import 'package:pscreen_home/features/remote_control/presentation/chat_page.dart';
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

  @override
  void initState() {
    super.initState();
    _targets = ThreadTargetsStore.instance.targets;
    _storeSub = ThreadTargetsStore.instance.changes.listen((_) {
      if (!mounted) return;
      setState(() => _targets = ThreadTargetsStore.instance.targets);
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
    _storeSub?.cancel();
    _presenceSub?.cancel();
    _deviceSub?.cancel();
    super.dispose();
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
        return ListTile(
          leading: _OnlineDot(online: online),
          title: Text(target.displayName),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // 改名后第二行小字灰色显示原始账号，方便对照是哪台设备。
              if (renamed)
                Text(
                  account,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              Text(_subtitleOf(device, online)),
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
    final TextEditingController controller = TextEditingController(
      text: target.alias,
    );
    final String? alias = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('重命名设备'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 20,
          decoration: InputDecoration(
            labelText: '备注名',
            hintText: target.account,
            helperText: '留空则显示原始账号',
            counterText: '',
          ),
          onSubmitted: (String value) => Navigator.of(context).pop(value),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
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
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('移除'),
          ),
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
    final String scene =
        online ? (device?.scene['title']?.toString() ?? '') : '';
    return scene.isEmpty ? '$kind · $status' : '$kind · $status · $scene';
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
