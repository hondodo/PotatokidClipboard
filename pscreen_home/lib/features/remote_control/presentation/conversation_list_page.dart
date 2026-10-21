import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pscreen_home/core/di/injection.dart';
import 'package:pscreen_home/features/remote_control/data/nim_client.dart';
import 'package:pscreen_home/features/remote_control/application/conversation_list_cubit.dart';
import 'package:pscreen_home/features/remote_control/presentation/chat_page.dart';
import 'package:pscreen_home/features/remote_control/data/tv_directory.dart';

/// 会话列表（管理员 Tab 2）。
class ConversationListPage extends StatelessWidget {
  const ConversationListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ConversationListCubit>(
      create: (_) => ConversationListCubit(
        source: NimConversationSource(nim: Injection.get<NimClient>()),
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
              title: Text(item.title),
              subtitle: Text(
                item.lastMessage,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: item.unread > 0
                  ? CircleAvatar(
                      radius: 12,
                      child: Text('${item.unread}',
                          style: const TextStyle(fontSize: 12)),
                    )
                  : null,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ChatPage(
                    account: item.account,
                    title: item.title,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
