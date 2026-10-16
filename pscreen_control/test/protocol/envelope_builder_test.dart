import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_control/features/protocol/envelope_builder.dart';

void main() {
  test('纯文本不加信封', () {
    expect(buildPlainText('你好'), '你好');
  });

  test('volume_up 命令生成正确信封', () {
    final String s = buildVolumeCommand('volume_up');
    final Map<String, dynamic> m = jsonDecode(s) as Map<String, dynamic>;
    expect(m['t'], 'cmd');
    expect(m['name'], 'volume_up');
  });

  test('channel 命令带 args', () {
    final String s = buildChannelCommand(name: 'CCTV-1');
    final Map<String, dynamic> m = jsonDecode(s) as Map<String, dynamic>;
    expect(m['t'], 'cmd');
    expect(m['name'], 'channel');
    expect(m['args']['name'], 'CCTV-1');
  });

  test('channel 按序号命令', () {
    final String s = buildChannelCommand(index: 3);
    final Map<String, dynamic> m = jsonDecode(s) as Map<String, dynamic>;
    expect(m['args']['index'], 3);
  });

  test('text 命令带 content', () {
    final String s = buildTextCommand('集合吃饭');
    final Map<String, dynamic> m = jsonDecode(s) as Map<String, dynamic>;
    expect(m['t'], 'cmd');
    expect(m['name'], 'text');
    expect(m['args']['content'], '集合吃饭');
  });

  test('buildCommandEnvelope 通用入口', () {
    final String s = buildCommandEnvelope('mute');
    final Map<String, dynamic> m = jsonDecode(s) as Map<String, dynamic>;
    expect(m, <String, dynamic>{'t': 'cmd', 'name': 'mute'});
    final String s2 = buildCommandEnvelope('channel', <String, dynamic>{'index': 5});
    final Map<String, dynamic> m2 = jsonDecode(s2) as Map<String, dynamic>;
    expect(m2['args']['index'], 5);
  });
}
