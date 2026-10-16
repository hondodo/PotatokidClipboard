import 'package:nim_core_v2/nim_core.dart';
// ignore: depend_on_referenced_packages
import 'package:nim_core_v2_platform_interface/nim_core_v2_platform_interface.dart'
    hide Log;

import 'package:pscreen_control/core/nim_client.dart';
import 'package:pscreen_control/features/admin/application/conversation_list_cubit.dart';

/// 会话数据源抽象（生产为 NIM SDK；测试 Fake）。
abstract class ConversationSource {
  Future<List<ConversationItem>> fetch();
  Stream<void> get onChange;
}

/// NIM SDK 会话数据源。
class NimConversationSource implements ConversationSource {
  NimConversationSource({required this.nim});

  final NimClient nim;

  @override
  Future<List<ConversationItem>> fetch() async {
    final NIMResult<NIMConversationResult> result =
        await nim.conversationService.getConversationList(0, 100);
    final List<NIMConversation> list =
        result.data?.conversationList ?? <NIMConversation>[];
    return list.map((NIMConversation c) {
      final String account = c.conversationId;
      return ConversationItem(
        account: account,
        title: account,
        lastMessage: _previewOf(c),
        unread: c.unreadCount ?? 0,
      );
    }).toList();
  }

  String _previewOf(NIMConversation c) {
    final NIMLastMessage? last = c.lastMessage;
    if (last == null) return '';
    if (last.messageType == NIMMessageType.text) return last.text ?? '';
    return '[非文本]';
  }

  @override
  Stream<void> get onChange => nim.conversationService.onConversationChanged;
}
