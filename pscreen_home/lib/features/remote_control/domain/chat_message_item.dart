/// 聊天消息条目（UI 用）。
///
/// 独立文件：避免数据层与页面循环 import。
class ChatMessageItem {
  const ChatMessageItem({required this.text, required this.isOutgoing});

  final String text;
  final bool isOutgoing;
}
