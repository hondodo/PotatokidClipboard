import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pscreen_home/core/di/injection.dart';
import 'package:pscreen_home/features/remote_control/core/control_config.dart';
import 'package:pscreen_home/features/remote_control/data/control_settings.dart';
import 'package:pscreen_home/features/remote_control/domain/chat_message_item.dart';
import 'package:pscreen_home/features/remote_control/presentation/widgets/command_panel.dart';
import 'package:pscreen_screen/core/network/realtime_channel.dart';

/// 聊天页：消息流（实时通道） + 底部输入（文本/命令）。
class ChatPage extends StatefulWidget {
  const ChatPage({super.key, required this.account, required this.title});

  final String account;
  final String title;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _text = TextEditingController();
  final List<ChatMessageItem> _messages = <ChatMessageItem>[];
  StreamSubscription<RealtimeMessage>? _msgSub;
  bool _historyLoaded = false;

  RealtimeChannel get _channel => Injection.get<RealtimeChannel>();

  bool get _isAdminSelf =>
      ControlSettings.instance.account == ControlConfig.adminAccount && widget.account == ControlConfig.adminAccount;

  @override
  void initState() {
    super.initState();
    // 进入聊天页即标为已读，并拉取历史（fire-and-forget）。
    _channel.markRead(widget.account);
    unawaited(_loadHistory());
    // 实时消息只投递寻址到本账号的帧；这里再按对方账号过滤。
    _msgSub = _channel.messages.listen((RealtimeMessage message) {
      if (!mounted || message.from != widget.account) return;
      setState(() {
        _messages.insert(0, ChatMessageItem(text: message.body, isOutgoing: false));
      });
    });
  }

  Future<void> _loadHistory() async {
    try {
      final List<RealtimeMessage> history = await _channel.fetchHistory(widget.account);
      if (!mounted || history.isEmpty) return;
      setState(() {
        // 历史按时间升序；列表 reverse: true，最新消息放索引 0。
        _messages.insertAll(
          0,
          history
              .where((RealtimeMessage m) => m.body.isNotEmpty)
              .map((RealtimeMessage m) => ChatMessageItem(text: m.body, isOutgoing: m.from != widget.account))
              .toList()
              .reversed,
        );
        _historyLoaded = true;
      });
    } catch (_) {
      // 历史拉取失败不阻断实时收发。
    }
  }

  @override
  void dispose() {
    _msgSub?.cancel();
    _text.dispose();
    super.dispose();
  }

  Future<void> _send(String body) async {
    if (body.isEmpty) return;
    // 管理员登录时不允许给 adminAccount（自己）发消息。
    if (_isAdminSelf) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('不能给自己发消息')));
      return;
    }
    final bool ok = await _channel.sendText(to: widget.account, body: body);
    if (!mounted) return;
    if (ok) {
      setState(() {
        _messages.insert(0, ChatMessageItem(text: body, isOutgoing: true));
      });
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? '已发送' : '发送失败')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: <Widget>[
          Expanded(
            child: _historyLoaded || _messages.isNotEmpty
                ? ListView.builder(
                    reverse: true,
                    itemCount: _messages.length,
                    itemBuilder: (BuildContext context, int i) {
                      final ChatMessageItem m = _messages[i];
                      return Align(
                        alignment: m.isOutgoing ? Alignment.centerRight : Alignment.centerLeft,
                        child: Card(
                          child: Padding(padding: const EdgeInsets.all(8), child: Text(m.text)),
                        ),
                      );
                    },
                  )
                : const Center(child: Text('暂无消息')),
          ),
          CommandPanel(onCommand: (String body) => _send(body)),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _text,
                    decoration: const InputDecoration(hintText: '输入消息'),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: () {
                    final String body = _text.text.trim();
                    _text.clear();
                    _send(body);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
