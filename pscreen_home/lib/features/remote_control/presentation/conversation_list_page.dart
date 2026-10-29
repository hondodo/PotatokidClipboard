import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pscreen_home/core/di/injection.dart';
import 'package:pscreen_home/features/remote_control/data/thread_targets_store.dart';
import 'package:pscreen_home/features/remote_control/presentation/chat_page.dart';
import 'package:pscreen_screen/core/network/realtime_channel.dart';

/// 遥控会话列表：只显示本机通过「+」添加过的目标设备。
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
  List<String> _targets = const <String>[];

  @override
  void initState() {
    super.initState();
    _targets = ThreadTargetsStore.instance.targets;
    _storeSub = ThreadTargetsStore.instance.changes.listen((_) {
      if (!mounted) return;
      setState(() => _targets = ThreadTargetsStore.instance.targets);
    });
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
        final String account = _targets[index];
        final RealtimeDeviceState? device = _channel.deviceInfoOf(account);
        final bool online = _channel.isOnline(account);
        return ListTile(
          leading: _OnlineDot(online: online),
          title: Text(account),
          subtitle: Text(_subtitleOf(device, online)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ChatPage(account: account, title: account),
            ),
          ),
        );
      },
    );
  }

  /// 副标题：设备类型 + 在线状态。
  String _subtitleOf(RealtimeDeviceState? device, bool online) {
    final String kind = switch (device?.kind) {
      'home' => '中控屏',
      'tv' => '电视',
      null || '' => '未知设备',
      _ => '设备',
    };
    final String status = online ? '在线' : '离线';
    final String scene = device?.scene['title']?.toString() ?? '';
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
