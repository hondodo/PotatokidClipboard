import 'package:flutter/material.dart';
import 'package:pscreen_home/features/remote_control/presentation/conversation_list_page.dart';
import 'package:pscreen_home/features/remote_control/presentation/send_page.dart';

/// 遥控页：两个 tab —— 遥控面板（发指令）与会话列表（聊天记录）。
///
/// 遥控面板直接复用迁移过来的 `SendPage`（内部按登录账号分叉：
/// 管理员看到多选广播页，家人看到单选页）。
class RemoteControlPage extends StatelessWidget {
  const RemoteControlPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('遥控'),
          bottom: const TabBar(
            tabs: <Widget>[
              Tab(text: '遥控面板'),
              Tab(text: '会话'),
            ],
          ),
        ),
        body: const TabBarView(
          children: <Widget>[
            SendPage(),
            ConversationListPage(),
          ],
        ),
      ),
    );
  }
}
