import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pscreen_control/app/di/injection.dart';
import 'package:pscreen_control/core/chat_message_item.dart';
import 'package:pscreen_control/core/nim_client.dart';
import 'package:pscreen_control/features/send/presentation/widgets/command_panel.dart';

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
  late final Stream<List<ChatMessageItem>> _messages;

  @override
  void initState() {
    super.initState();
    _messages = getIt<NimClient>().watchMessages(widget.account);
    // 进入聊天页即标为已读（内部 fire-and-forget，失败仅记日志）。
    unawaited(getIt<NimClient>().markConversationRead(widget.account));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send(String body) async {
    if (body.isEmpty) return;
    final bool ok = await getIt<NimClient>()
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
            child: StreamBuilder<List<ChatMessageItem>>(
              stream: _messages,
              builder: (BuildContext context, AsyncSnapshot snapshot) {
                final List<ChatMessageItem> items =
                    snapshot.data as List<ChatMessageItem>? ??
                        <ChatMessageItem>[];
                return ListView.builder(
                  reverse: true,
                  itemCount: items.length,
                  itemBuilder: (BuildContext context, int i) {
                    final ChatMessageItem m = items[i];
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
