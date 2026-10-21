import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pscreen_home/core/di/injection.dart';
import 'package:pscreen_home/features/remote_control/domain/chat_message_item.dart';
import 'package:pscreen_home/features/remote_control/data/nim_client.dart';
import 'package:pscreen_home/features/remote_control/presentation/widgets/command_panel.dart';

/// 聊天页：消息流（NIM 实时） + 底部输入（文本/命令）。
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
  StreamSubscription<List<ChatMessageItem>>? _msgSub;

  @override
  void initState() {
    super.initState();
    // 进入聊天页即标为已读（内部 fire-and-forget，失败仅记日志）。
    unawaited(Injection.get<NimClient>().markConversationRead(widget.account));
    // 流按批次到达（批内旧→新）；reversed 后 insertAll(0) 使最新在索引 0，
    // 配合 ListView(reverse: true) 最新消息显示在底部。
    _msgSub = Injection.get<NimClient>()
        .watchMessages(widget.account)
        .listen((List<ChatMessageItem> batch) {
      if (!mounted || batch.isEmpty) return;
      setState(() => _messages.insertAll(0, batch.reversed));
    });
  }

  @override
  void dispose() {
    _msgSub?.cancel();
    _text.dispose();
    super.dispose();
  }

  Future<void> _send(String body) async {
    if (body.isEmpty) return;
    final bool ok = await Injection.get<NimClient>()
        .sendText(toAccount: widget.account, text: body);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? '已发送' : '发送失败')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: <Widget>[
          Expanded(
            child: ListView.builder(
              reverse: true,
              itemCount: _messages.length,
              itemBuilder: (BuildContext context, int i) {
                final ChatMessageItem m = _messages[i];
                return Align(
                  alignment: m.isOutgoing
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(m.text),
                    ),
                  ),
                );
              },
            ),
          ),
          CommandPanel(
            onCommand: (String body) => _send(body),
          ),
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
