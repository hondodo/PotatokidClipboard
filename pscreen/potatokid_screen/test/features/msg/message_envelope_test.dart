import 'package:flutter_test/flutter_test.dart';
import 'package:potatokid_screen/features/msg/protocol/message_envelope.dart';

void main() {
  test('纯文本 → plainText', () {
    final ParsedMessage m = parseIncomingText('你好');
    expect(m.kind, EnvelopeKind.plainText);
    expect(m.plainText, '你好');
  });

  test('合法 txt 信封 → text', () {
    final ParsedMessage m =
        parseIncomingText('{"t":"txt","content":"你好"}');
    expect(m.kind, EnvelopeKind.text);
    expect(m.content, '你好');
  });

  test('合法 cmd 信封 → command', () {
    final ParsedMessage m =
        parseIncomingText('{"t":"cmd","name":"volume_up"}');
    expect(m.kind, EnvelopeKind.command);
    expect(m.commandName, 'volume_up');
    expect(m.args, isNull);
  });

  test('前后空白容忍', () {
    final ParsedMessage m =
        parseIncomingText('  {"t":"cmd","name":"mute"}  ');
    expect(m.kind, EnvelopeKind.command);
    expect(m.commandName, 'mute');
  });

  test('cmd 信封带 args', () {
    final ParsedMessage m = parseIncomingText(
        '{"t":"cmd","name":"channel","args":{"name":"CCTV-1"}}');
    expect(m.kind, EnvelopeKind.command);
    expect(m.args?['name'], 'CCTV-1');
  });

  test('坏 JSON → plainText 回退', () {
    final ParsedMessage m = parseIncomingText('{broken');
    expect(m.kind, EnvelopeKind.plainText);
    expect(m.plainText, '{broken');
  });

  test('无 t 字段 JSON → plainText 回退', () {
    final ParsedMessage m = parseIncomingText('{"foo":"bar"}');
    expect(m.kind, EnvelopeKind.plainText);
    expect(m.plainText, '{"foo":"bar"}');
  });

  test('未知 t 值 → plainText 回退', () {
    final ParsedMessage m = parseIncomingText('{"t":"unknown","x":1}');
    expect(m.kind, EnvelopeKind.plainText);
    expect(m.plainText, '{"t":"unknown","x":1}');
  });

  test('cmd 无 name → plainText 回退', () {
    final ParsedMessage m = parseIncomingText('{"t":"cmd"}');
    expect(m.kind, EnvelopeKind.plainText);
    expect(m.plainText, '{"t":"cmd"}');
  });
}
