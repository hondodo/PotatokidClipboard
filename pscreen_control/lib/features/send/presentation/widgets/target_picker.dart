import 'package:flutter/material.dart';
import 'package:pscreen_control/features/send/data/tv_directory.dart';

/// 目标选择器：预设列表多选 + 手动输入 + 扫码。
class TargetPicker extends StatelessWidget {
  const TargetPicker({
    super.key,
    required this.devices,
    required this.selected,
    required this.onToggle,
    required this.onScan,
    required this.manualController,
    required this.onManualAdd,
  });

  final List<TvDevice> devices;
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  final VoidCallback onScan;
  final TextEditingController manualController;
  final VoidCallback onManualAdd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text('目标（已选 ${selected.length}）',
                style: Theme.of(context).textTheme.titleSmall),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.qr_code_scanner),
              tooltip: '扫码添加',
              onPressed: onScan,
            ),
          ],
        ),
        SizedBox(
          height: 180,
          child: ListView(
            children: devices
                .map((TvDevice d) => CheckboxListTile(
                      title: Text(d.name),
                      subtitle: Text(d.account),
                      value: selected.contains(d.account),
                      onChanged: (_) => onToggle(d.account),
                    ))
                .toList(),
          ),
        ),
        Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: manualController,
                decoration: const InputDecoration(
                  hintText: '手动输入账号',
                  isDense: true,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: onManualAdd,
            ),
          ],
        ),
      ],
    );
  }
}
