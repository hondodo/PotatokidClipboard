part of 'conversation_list_cubit.dart';

/// 会话列表状态。
class ConversationListState extends Equatable {
  const ConversationListState({this.items = const <ConversationItem>[]});

  final List<ConversationItem> items;

  @override
  List<Object?> get props => <Object?>[items];
}
