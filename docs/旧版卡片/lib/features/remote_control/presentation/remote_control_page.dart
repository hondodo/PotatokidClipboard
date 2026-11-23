import 'package:flutter/material.dart';
import 'package:pscreen_home/features/remote_control/data/thread_targets_store.dart';
import 'package:pscreen_home/features/remote_control/presentation/conversation_list_page.dart';
import 'package:pscreen_home/features/remote_control/presentation/qr_scan_page.dart';

/// 遥控会话页：只保留会话列表，右上角「+」添加目标设备。
class RemoteControlPage extends StatelessWidget {
  const RemoteControlPage({super.key});

  Future<void> _addTarget(BuildContext context) async {
    final String? account = await showDialog<String>(
      context: context,
      builder: (_) => const _AddTargetDialog(),
    );
    if (account == null || account.isEmpty) return;
    final bool added = await ThreadTargetsStore.instance.add(account);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(added ? '已添加 $account' : '$account 已在列表中')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('遥控会话'),
        actions: <Widget>[
          IconButton(
            tooltip: '添加设备',
            icon: const Icon(Icons.add),
            onPressed: () => _addTarget(context),
          ),
        ],
      ),
      body: const ConversationListPage(),
    );
  }
}

/// 添加设备弹窗：手动输入账号，或跳转扫码页带回账号。
class _AddTargetDialog extends StatefulWidget {
  const _AddTargetDialog();

  @override
  State<_AddTargetDialog> createState() => _AddTargetDialogState();
}

class _AddTargetDialogState extends State<_AddTargetDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final String? account = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(builder: (_) => const QrScanPage()),
    );
    if (!mounted || account == null || account.isEmpty) return;
    _controller.text = account;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('添加设备'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '设备账号',
              hintText: '例如 tangde304',
            ),
            onSubmitted: (String value) => Navigator.of(context).pop(value.trim()),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _scan,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('扫码输入'),
            ),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('添加'),
        ),
      ],
    );
  }
}
