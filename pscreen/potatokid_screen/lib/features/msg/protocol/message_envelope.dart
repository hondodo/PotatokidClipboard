import 'dart:convert';

/// 解析结果种类。
enum EnvelopeKind { plainText, text, command }

/// 解析结果。
class ParsedMessage {
  const ParsedMessage.plain(String raw)
      : kind = EnvelopeKind.plainText,
        plainText = raw,
        content = null,
        commandName = null,
        args = null;

  const ParsedMessage.text(this.content)
      : kind = EnvelopeKind.text,
        plainText = null,
        commandName = null,
        args = null;

  const ParsedMessage.command(this.commandName, this.args)
      : kind = EnvelopeKind.command,
        plainText = null,
        content = null;

  final EnvelopeKind kind;
  final String? plainText;
  final String? content;
  final String? commandName;
  final Map<String, dynamic>? args;
}

/// 解析入站文本消息（设计 §3.1）。
///
/// - trim 后非 `{` 开头 → plainText
/// - `{` 开头但 JSON 解析失败 / 无 `t` / `t` 不认识 / `cmd` 无 `name` → plainText 回退（原样）
/// - `{"t":"txt","content":String}` → text
/// - `{"t":"cmd","name":String,"args":Map?}` → command
ParsedMessage parseIncomingText(String raw) {
  final String trimmed = raw.trim();
  if (!trimmed.startsWith('{')) {
    return ParsedMessage.plain(raw);
  }
  try {
    final dynamic decoded = jsonDecode(trimmed);
    if (decoded is! Map<String, dynamic>) {
      return ParsedMessage.plain(raw);
    }
    final dynamic t = decoded['t'];
    if (t == 'txt') {
      final dynamic content = decoded['content'];
      if (content is String) return ParsedMessage.text(content);
      return ParsedMessage.plain(raw);
    }
    if (t == 'cmd') {
      final dynamic name = decoded['name'];
      if (name is String && name.isNotEmpty) {
        final dynamic args = decoded['args'];
        return ParsedMessage.command(
            name, args is Map<String, dynamic> ? args : null);
      }
      return ParsedMessage.plain(raw);
    }
    return ParsedMessage.plain(raw);
  } catch (_) {
    return ParsedMessage.plain(raw);
  }
}
