import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/features/remote_control/application/conversation_source.dart';

void main() {
  test('裸账号原样返回', () {
    expect(peerAccountFromConversationId('TV_001', 'me'), 'TV_001');
  });

  test('p2p|me|them 提取对方账号', () {
    expect(peerAccountFromConversationId('p2p|me|them', 'me'), 'them');
  });

  test('p2p|them|me 提取对方账号', () {
    expect(peerAccountFromConversationId('p2p|them|me', 'me'), 'them');
  });

  test('team 会话无匹配时返回目标 id（不含类型前缀）', () {
    expect(peerAccountFromConversationId('team|team_9', 'me'), 'team_9');
  });

  test('两段均等于自己时原样返回', () {
    expect(peerAccountFromConversationId('p2p|me|me', 'me'), 'p2p|me|me');
  });

  test('空段被忽略', () {
    expect(peerAccountFromConversationId('p2p||them', 'me'), 'them');
  });
}
