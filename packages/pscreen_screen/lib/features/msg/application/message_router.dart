import 'package:pscreen_screen/app/app_log.dart';
import 'package:pscreen_screen/features/msg/application/message_command_executor.dart';
import 'package:pscreen_screen/features/msg/application/message_overlay_controller.dart';
import 'package:pscreen_screen/features/msg/protocol/message_envelope.dart';

/// 入站消息分流：文本 → 浮层；命令 → 执行器（text 命令特例走浮层）。
class MessageRouter {
  MessageRouter({required this.overlay, required this.executor});

  final MessageOverlayController overlay;
  final MessageCommandExecutor executor;

  void handleIncoming(String raw) {
    final ParsedMessage msg = parseIncomingText(raw);
    switch (msg.kind) {
      case EnvelopeKind.plainText:
        if (msg.plainText != null && msg.plainText!.isNotEmpty) {
          overlay.show(msg.plainText!);
        }
        break;
      case EnvelopeKind.text:
        if (msg.content != null && msg.content!.isNotEmpty) {
          overlay.show(msg.content!);
        }
        break;
      case EnvelopeKind.command:
        final String name = msg.commandName ?? '';
        if (name.isEmpty) break;
        if (name == 'text') {
          final dynamic content = msg.args?['content'];
          if (content is String && content.isNotEmpty) {
            overlay.show(content);
          }
          break;
        }
        if (!executor.execute(name, msg.args)) {
          Log.i('[MessageRouter] 忽略未知/无效命令: $name ${msg.args}');
        }
        break;
    }
  }
}
