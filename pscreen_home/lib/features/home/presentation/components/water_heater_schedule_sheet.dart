import 'package:flutter/material.dart';
import 'package:pscreen_home/features/home/domain/models/water_heater_schedule.dart';

/// 定时预热编辑面板：5 个时段，重复类型 / 开始结束时间 / 单段开关。
///
/// HA 把定时表存成一个编码 text：
/// `类型&开始&结束&开关&id-...`，这里负责解析、编辑后再写回。
/// 重复类型先支持「仅一次 / 每天」；其余 token 未验证，暂不提供选择。
class WaterHeaterScheduleSheet extends StatefulWidget {
  const WaterHeaterScheduleSheet({
    super.key,
    required this.scheduleText,
    required this.masterOn,
    required this.onWrite,
    this.onMasterToggle,
  });

  final String? scheduleText;
  final bool masterOn;
  final ValueChanged<String> onWrite;
  final VoidCallback? onMasterToggle;

  @override
  State<WaterHeaterScheduleSheet> createState() =>
      _WaterHeaterScheduleSheetState();
}

class _WaterHeaterScheduleSheetState extends State<WaterHeaterScheduleSheet> {
  late PreheatSchedule _schedule =
      PreheatSchedule.parse(widget.scheduleText);
  late bool _masterOn = widget.masterOn;

  static String _timeLabel(int minutes) {
    final int hour = (minutes ~/ 60) % 24;
    final int minute = minutes % 60;
    return '${hour.toString().padLeft(2, '0')}:'
        '${minute.toString().padLeft(2, '0')}';
  }

  void _write() => widget.onWrite(_schedule.encode());

  Future<void> _toggleSlot(int index, bool enabled) async {
    setState(() {
      _schedule = _schedule.replace(
        index,
        _schedule.slots[index].copyWith(enabled: enabled),
      );
    });
    _write();
  }

  Future<void> _editSlot(int index) async {
    final PreheatSlot? result = await showDialog<PreheatSlot>(
      context: context,
      builder: (BuildContext context) => _SlotEditor(
        slot: _schedule.slots[index],
        index: index,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _schedule = _schedule.replace(index, result);
    });
    _write();
  }

  void _addSlot() {
    final int index =
        _schedule.slots.indexWhere((PreheatSlot slot) => slot.isEmpty);
    if (index < 0) return;
    final PreheatSlot slot = PreheatSlot(
      repeat: PreheatRepeat.once,
      startMinutes: 8 * 60,
      endMinutes: 8 * 60 + 30,
      enabled: true,
      id: index,
    );
    setState(() {
      _schedule = _schedule.replace(index, slot);
    });
    _write();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool canAdd =
        _schedule.slots.any((PreheatSlot slot) => slot.isEmpty);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '定时预热',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: '关闭',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('定时预热总开关'),
            subtitle: const Text('开启后按下面的时段执行'),
            value: _masterOn,
            onChanged: widget.onMasterToggle == null
                ? null
                : (bool value) {
                    setState(() => _masterOn = value);
                    widget.onMasterToggle!();
                  },
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.separated(
              itemCount: _schedule.slots.length,
              separatorBuilder: (BuildContext context, int index) =>
                  const Divider(height: 1),
              itemBuilder: (BuildContext context, int index) {
                final PreheatSlot slot = _schedule.slots[index];
                if (slot.isEmpty) {
                  return ListTile(
                    leading: Icon(
                      Icons.add_circle_outline_rounded,
                      color: theme.colorScheme.outline,
                    ),
                    title: Text(
                      '空时段 ${index + 1}',
                      style: TextStyle(color: theme.colorScheme.outline),
                    ),
                    onTap: () => _editSlot(index),
                  );
                }
                return ListTile(
                  leading: const Icon(Icons.schedule_rounded),
                  title: Text(
                    '${_timeLabel(slot.startMinutes)}–'
                    '${_timeLabel(slot.endMinutes)}',
                  ),
                  subtitle: Text(slot.repeat.label),
                  trailing: Switch(
                    value: slot.enabled,
                    onChanged: (bool value) => _toggleSlot(index, value),
                  ),
                  onTap: () => _editSlot(index),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: canAdd ? _addSlot : null,
              icon: const Icon(Icons.add_rounded),
              label: const Text('添加时段'),
            ),
          ),
        ],
      ),
    );
  }
}

/// 单个时段的编辑对话框。
class _SlotEditor extends StatefulWidget {
  const _SlotEditor({required this.slot, required this.index});

  final PreheatSlot slot;
  final int index;

  @override
  State<_SlotEditor> createState() => _SlotEditorState();
}

class _SlotEditorState extends State<_SlotEditor> {
  late PreheatRepeat _repeat;
  late int _start;
  late int _end;

  @override
  void initState() {
    super.initState();
    _repeat = widget.slot.repeat;
    _start = widget.slot.startMinutes;
    _end = widget.slot.endMinutes;
    if (_start == 0 && _end == 0) {
      _start = 8 * 60;
      _end = 8 * 60 + 30;
    }
  }

  Future<void> _pickTime({required bool start}) async {
    final int minutes = start ? _start : _end;
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
    );
    if (picked == null) return;
    setState(() {
      final int value = picked.hour * 60 + picked.minute;
      if (start) {
        _start = value;
      } else {
        _end = value;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('时段 ${widget.index + 1}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          DropdownButtonFormField<PreheatRepeat>(
            initialValue: _repeat,
            decoration: const InputDecoration(labelText: '重复'),
            items: const <DropdownMenuItem<PreheatRepeat>>[
              DropdownMenuItem<PreheatRepeat>(
                value: PreheatRepeat.once,
                child: Text('仅一次'),
              ),
              DropdownMenuItem<PreheatRepeat>(
                value: PreheatRepeat.daily,
                child: Text('每天'),
              ),
            ],
            onChanged: (PreheatRepeat? value) {
              if (value != null) setState(() => _repeat = value);
            },
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('开始时间'),
            trailing: Text(_label(_start)),
            onTap: () => _pickTime(start: true),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('结束时间'),
            trailing: Text(_label(_end)),
            onTap: () => _pickTime(start: false),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop(PreheatSlot(
              repeat: _repeat,
              startMinutes: _start,
              endMinutes: _end,
              enabled: true,
              id: widget.slot.isEmpty ? widget.index : widget.slot.id,
            ));
          },
          child: const Text('保存'),
        ),
      ],
    );
  }

  static String _label(int minutes) {
    final int hour = (minutes ~/ 60) % 24;
    final int minute = minutes % 60;
    return '${hour.toString().padLeft(2, '0')}:'
        '${minute.toString().padLeft(2, '0')}';
  }
}
