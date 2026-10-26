import 'package:pscreen_home/features/remote_control/application/conversation_list_cubit.dart';
import 'package:pscreen_screen/core/network/realtime_channel.dart';

/// 会话数据源抽象（生产为实时通道；测试 Fake）。
abstract class ConversationSource {
  Future<List<ConversationItem>> fetch();
  Stream<void> get onChange;

  /// 在线状态变更通知（用于刷新会话条目的在线圆点）。
  Stream<void> get presenceChanges;

  /// 账号当前是否在线。
  bool isOnline(String account);
}

/// 实时通道会话数据源：服务端按历史消息聚合最近消息与未读数。
class RealtimeConversationSource implements ConversationSource {
  RealtimeConversationSource({required this.channel});

  final RealtimeChannel channel;

  @override
  Future<List<ConversationItem>> fetch() async {
    final List<RealtimeConversation> list = await channel.fetchConversations();
    return list
        .where((RealtimeConversation c) => c.account.isNotEmpty)
        .map(
          (RealtimeConversation c) => ConversationItem(
            account: c.account,
            title: c.account,
            lastMessage: c.lastMessage,
            unread: c.unread,
            online: channel.onlineAccounts.contains(c.account),
          ),
        )
        .toList(growable: false);
  }

  @override
  Stream<void> get onChange => channel.conversationsChanged;

  @override
  Stream<void> get presenceChanges => channel.presence.map<void>((RealtimePresence _) {});

  @override
  bool isOnline(String account) => channel.onlineAccounts.contains(account);
}
