/// 聊天消息条目（UI 用）。
///
/// 独立文件：避免 nim_client 与 chat_page 循环 import。
class ChatMessageItem {
  const ChatMessageItem({required this.text, required this.isOutgoing});

  final String text;
  final bool isOutgoing;
}
