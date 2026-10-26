import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pscreen_home/core/di/injection.dart';
import 'package:pscreen_home/features/remote_control/application/conversation_list_cubit.dart';
import 'package:pscreen_home/features/remote_control/presentation/chat_page.dart';
import 'package:pscreen_home/features/remote_control/data/tv_directory.dart';
import 'package:pscreen_screen/core/network/realtime_channel.dart';

/// 会话列表（管理员 Tab 2）。
class ConversationListPage extends StatelessWidget {
  const ConversationListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ConversationListCubit>(
      create: (_) => ConversationListCubit(
        source: RealtimeConversationSource(channel: Injection.get<RealtimeChannel>()),
        nameOf: Injection.get<TvDirectory>().nameOf,
      )..refresh(),
      child: const _ConversationListView(),
    );
  }
}

class _ConversationListView extends StatelessWidget {
  const _ConversationListView();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ConversationListCubit, ConversationListState>(
      builder: (BuildContext context, ConversationListState state) {
        if (state.items.isEmpty) {
          return const Center(child: Text('暂无会话'));
        }
        return ListView.builder(
          itemCount: state.items.length,
          itemBuilder: (BuildContext context, int i) {
            final ConversationItem item = state.items[i];
            return ListTile(
              title: Row(
                children: <Widget>[
                  _OnlineDot(online: item.online),
                  const SizedBox(width: 8),
                  Expanded(child: Text(item.title)),
                ],
              ),
              subtitle: Text(item.lastMessage, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: item.unread > 0
                  ? CircleAvatar(radius: 12, child: Text('${item.unread}', style: const TextStyle(fontSize: 12)))
                  : null,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ChatPage(account: item.account, title: item.title),
                ),
              ),
            );
          },
        );
      },
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
