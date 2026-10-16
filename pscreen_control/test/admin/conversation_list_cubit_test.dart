import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_control/features/admin/application/conversation_list_cubit.dart';

class FakeSource implements ConversationSource {
  List<ConversationItem> data = <ConversationItem>[];
  final StreamController<void> _ctrl = StreamController<void>.broadcast();

  @override
  Future<List<ConversationItem>> fetch() async => data;

  @override
  Stream<void> get onChange => _ctrl.stream;

  void notify() => _ctrl.add(null);
}

void main() {
  test('refresh 发射列表', () async {
    final FakeSource source = FakeSource()
      ..data = <ConversationItem>[
        const ConversationItem(
            account: 'TV_001',
            title: '客厅电视',
            lastMessage: '你好',
            unread: 2),
      ];
    final ConversationListCubit cubit = ConversationListCubit(
      source: source,
      nameOf: (String a) => a == 'TV_001' ? '客厅电视' : a,
    );
    await cubit.refresh();
    expect(cubit.state.items.single.title, '客厅电视');
    expect(cubit.state.items.single.unread, 2);
    await cubit.close();
  });

  test('source 变更触发 refresh', () async {
    final FakeSource source = FakeSource();
    final ConversationListCubit cubit = ConversationListCubit(
      source: source,
      nameOf: (String a) => a,
    );
    source.data = <ConversationItem>[
      const ConversationItem(
          account: 'TV_002', title: 'TV_002', lastMessage: '', unread: 0),
    ];
    source.notify();
    await pumpEventQueue();
    expect(cubit.state.items.single.account, 'TV_002');
    await cubit.close();
  });
}
