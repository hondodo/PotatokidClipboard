import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:pscreen_home/features/remote_control/core/control_log.dart';

import 'conversation_source.dart';

export 'conversation_source.dart' show ConversationSource, RealtimeConversationSource;

part 'conversation_list_state.dart';

/// 会话条目（UI 用）。
class ConversationItem extends Equatable {
  const ConversationItem({
    required this.account,
    required this.title,
    required this.lastMessage,
    required this.unread,
    this.online = false,
  });

  final String account;
  final String title;
  final String lastMessage;
  final int unread;

  /// 该账号当前是否在线（由实时通道的在线列表决定）。
  final bool online;

  ConversationItem copyWith({bool? online}) => ConversationItem(
    account: account,
    title: title,
    lastMessage: lastMessage,
    unread: unread,
    online: online ?? this.online,
  );

  @override
  List<Object?> get props => <Object?>[account, title, lastMessage, unread, online];
}

/// 会话列表 Cubit：实时通道会话驱动，title 经 nameOf 映射。
class ConversationListCubit extends Cubit<ConversationListState> {
  ConversationListCubit({required this.source, required this.nameOf}) : super(const ConversationListState()) {
    _sub = source.onChange.listen((_) {
      unawaited(refresh());
    });
    _presenceSub = source.presenceChanges.listen((_) {
      _applyPresence();
    });
  }

  final ConversationSource source;
  final String Function(String account) nameOf;

  StreamSubscription<void>? _sub;
  StreamSubscription<void>? _presenceSub;

  Future<void> refresh() async {
    try {
      final List<ConversationItem> fetched = await source.fetch();
      if (isClosed) return;
      final List<ConversationItem> items = fetched
          .map(
            (ConversationItem item) => ConversationItem(
              account: item.account,
              title: nameOf(item.account),
              lastMessage: item.lastMessage,
              unread: item.unread,
              online: source.isOnline(item.account),
            ),
          )
          .toList();
      emit(ConversationListState(items: items));
    } catch (e) {
      // fetch 失败保持现有列表；已关闭则静默丢弃。
      if (isClosed) return;
      ControlLog.e('conversation refresh failed: $e');
    }
  }

  /// 在线状态变更无需重新拉取会话，仅就地刷新圆点。
  void _applyPresence() {
    if (isClosed || state.items.isEmpty) return;
    final List<ConversationItem> items = state.items
        .map((ConversationItem item) => item.copyWith(online: source.isOnline(item.account)))
        .toList();
    emit(ConversationListState(items: items));
  }

  @override
  Future<void> close() {
    _sub?.cancel();
    _presenceSub?.cancel();
    return super.close();
  }
}
