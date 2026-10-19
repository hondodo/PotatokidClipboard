import 'package:nim_core_v2/nim_core.dart';

import 'package:pscreen_control/app/storage/app_settings.dart';
import 'package:pscreen_control/app/utils/app_log.dart';
import 'package:pscreen_control/core/nim_client.dart';
import 'package:pscreen_control/features/admin/application/conversation_list_cubit.dart';

/// 会话数据源抽象（生产为 NIM SDK；测试 Fake）。
abstract class ConversationSource {
  Future<List<ConversationItem>> fetch();
  Stream<void> get onChange;
}

/// 从 conversationId 提取对方账号；无法解析时原样返回。
///
/// NIM V2 conversationId 格式为 `type|target|operator`（如 `p2p|acc1|acc2`）。
/// 类型前缀（p2p/team/superTeam/unknown）与自己的账号会被跳过；
/// 无匹配时返回原 conversationId。
String peerAccountFromConversationId(String cid, String myAccount) {
  if (!cid.contains('|')) return cid;
  const Set<String> typePrefixes = <String>{'p2p', 'team', 'superteam', 'unknown'};
  final List<String> parts = cid
      .split('|')
      .where((String p) =>
          p.isNotEmpty && !typePrefixes.contains(p.toLowerCase()))
      .toList();
  for (final String p in parts) {
    if (p != myAccount) return p;
  }
  return cid;
}

/// NIM SDK 会话数据源（使用本地会话服务：来消息自动更新的是本地会话列表）。
class NimConversationSource implements ConversationSource {
  NimConversationSource({required this.nim});

  final NimClient nim;

  @override
  Future<List<ConversationItem>> fetch() async {
    final NIMResult<NIMConversationResult> result =
        await nim.localConversationService.getConversationList(0, 100);
    final List<NIMConversation> list =
        result.data?.conversationList ?? <NIMConversation>[];
    final String myAccount = AppSettings.instance.nimAccount;
    final List<ConversationItem> items = <ConversationItem>[];
    for (final NIMConversation c in list) {
      // 仅展示 P2P 会话；team/superTeam 的 conversationId 不是对方账号。
      if (c.type != NIMConversationType.p2p) continue;
      final String account = await _peerAccountOf(c.conversationId, myAccount);
      items.add(ConversationItem(
        account: account,
        title: account,
        lastMessage: _previewOf(c),
        unread: c.unreadCount ?? 0,
      ));
    }
    return items;
  }

  /// 优先走 SDK `conversationTargetId`；失败时回退到本地解析。
  Future<String> _peerAccountOf(String cid, String myAccount) async {
    try {
      final NIMResult<String> target = await NimCore
          .instance.conversationIdUtil
          .conversationTargetId(cid);
      if (target.isSuccess &&
          target.data != null &&
          target.data!.isNotEmpty) {
        return target.data!;
      }
    } catch (e) {
      AppLog.e('[ConversationSource] conversationTargetId 异常: $e');
    }
    return peerAccountFromConversationId(cid, myAccount);
  }

  String _previewOf(NIMConversation c) {
    final NIMLastMessage? last = c.lastMessage;
    if (last == null) return '';
    if (last.messageType == NIMMessageType.text) return last.text ?? '';
    return '[非文本]';
  }

  @override
  Stream<void> get onChange =>
      nim.localConversationService.onConversationChanged;
}
