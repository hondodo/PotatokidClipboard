import 'package:flutter/material.dart';
import 'package:pscreen_home/features/parental/domain/parental_config.dart';

/// 儿童档案编辑弹窗（方案 4.2 模块①）：新增 / 编辑一份档案。
///
/// 字段按档位显隐（两档语义）：温和档显「隐藏分组 / 隐藏频道」黑名单，
/// 严格档显「白名单分组 / 白名单频道」；限额 / 时段 / `locked` 两档恒显。
/// 保存返回组装好的 [ParentalChild]（编辑时沿用原 id），取消返回 null。
class ChildProfileEditorSheet extends StatefulWidget {
  const ChildProfileEditorSheet({super.key, this.initial});

  /// 编辑目标；空 = 新增（保存时生成新 id）。
  final ParentalChild? initial;

  /// 打开编辑弹窗，返回选中的档案（取消为 null）。
  static Future<ParentalChild?> show(
    BuildContext context, {
    ParentalChild? initial,
  }) =>
      showModalBottomSheet<ParentalChild>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (BuildContext context) =>
            ChildProfileEditorSheet(initial: initial),
      );

  @override
  State<ChildProfileEditorSheet> createState() =>
      _ChildProfileEditorSheetState();
}

class _ChildProfileEditorSheetState extends State<ChildProfileEditorSheet> {
  late final TextEditingController _name;
  late final TextEditingController _age;
  late final TextEditingController _session;
  late final TextEditingController _daily;
  late final TextEditingController _quietHours;
  late final TextEditingController _hideGroups;
  late final TextEditingController _hideChannels;
  late final TextEditingController _allowGroups;
  late final TextEditingController _allowChannels;

  late String _profileMode;
  late bool _locked;
  String? _nameError;

  @override
  void initState() {
    super.initState();
    final ParentalChild? initial = widget.initial;
    _name = TextEditingController(text: initial?.name ?? '');
    _age = TextEditingController(text: '${initial?.age ?? ''}');
    _session = TextEditingController(text: '${initial?.sessionLimitMin ?? ''}');
    _daily = TextEditingController(text: '${initial?.dailyLimitMin ?? ''}');
    _quietHours = TextEditingController(text: initial?.quietHours.join('，') ?? '');
    _hideGroups = TextEditingController(text: initial?.hideGroups.join('，') ?? '');
    _hideChannels = TextEditingController(text: initial?.hideChannels.join('，') ?? '');
    _allowGroups = TextEditingController(text: initial?.allowGroups.join('，') ?? '');
    _allowChannels = TextEditingController(text: initial?.allowChannels.join('，') ?? '');
    _profileMode = initial?.profileMode ?? 'mild';
    _locked = initial?.locked ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    _age.dispose();
    _session.dispose();
    _daily.dispose();
    _quietHours.dispose();
    _hideGroups.dispose();
    _hideChannels.dispose();
    _allowGroups.dispose();
    _allowChannels.dispose();
    super.dispose();
  }

  bool get _isStrict => _profileMode == 'strict';

  void _save() {
    final String name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = '请填写名称');
      return;
    }
    final ParentalChild? initial = widget.initial;
    Navigator.of(context).pop(
      ParentalChild(
        id: initial?.id ?? 'c${DateTime.now().millisecondsSinceEpoch}',
        name: name,
        age: int.tryParse(_age.text.trim()),
        profileMode: _profileMode,
        hideGroups: _split(_hideGroups.text),
        hideChannels: _split(_hideChannels.text),
        allowGroups: _split(_allowGroups.text),
        allowChannels: _split(_allowChannels.text),
        sessionLimitMin: _limit(_session.text),
        dailyLimitMin: _limit(_daily.text),
        quietHours: _split(_quietHours.text),
        locked: _locked,
      ),
    );
  }

  /// 逗号 / 顿号 / 换行分隔的名单 → 去空串列表。
  static List<String> _split(String text) => text
      .split(RegExp(r'[,，、\n]'))
      .map((String item) => item.trim())
      .where((String item) => item.isNotEmpty)
      .toList(growable: false);

  /// 限额解析：空 / 非数字 / 0 视为不启用（null）。
  static int? _limit(String text) {
    final int? value = int.tryParse(text.trim());
    if (value == null || value <= 0) return null;
    return value;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Text(
                    widget.initial == null ? '添加儿童档案' : '编辑儿童档案',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: '关闭',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _name,
                decoration: InputDecoration(
                  labelText: '名称',
                  errorText: _nameError,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _age,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '年龄',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _session,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '单次限额(分钟)',
                        helperText: '空/0 = 不限',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _daily,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '单日限额(分钟)',
                        helperText: '空/0 = 不限',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _quietHours,
                      decoration: const InputDecoration(
                        labelText: '禁看时段',
                        hintText: '22:00-06:00，多个用逗号分隔',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text('档位', style: theme.textTheme.bodySmall),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: <Widget>[
                  ChoiceChip(
                    label: const Text('温和档（隐藏黑名单）'),
                    selected: !_isStrict,
                    onSelected: (_) => setState(() => _profileMode = 'mild'),
                  ),
                  ChoiceChip(
                    label: const Text('严格档（白名单）'),
                    selected: _isStrict,
                    onSelected: (_) => setState(() => _profileMode = 'strict'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                _isStrict
                    ? '严格档：仅播放白名单分组 / 白名单频道的交集。'
                    : '温和档：在全部频道基础上隐藏黑名单分组 / 黑名单频道。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
              const SizedBox(height: 12),
              // 可见性字段按档位显隐（两档语义，不共用一组字段）。
              if (_isStrict) ...<Widget>[
                TextField(
                  controller: _allowGroups,
                  decoration: const InputDecoration(
                    labelText: '白名单分组',
                    hintText: '📺央视频道，📺少儿频道',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _allowChannels,
                  decoration: const InputDecoration(
                    labelText: '白名单频道',
                    hintText: '*少儿*，CCTV1（支持 * 通配）',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ] else ...<Widget>[
                TextField(
                  controller: _hideGroups,
                  decoration: const InputDecoration(
                    labelText: '隐藏分组',
                    hintText: '📺购物频道',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _hideChannels,
                  decoration: const InputDecoration(
                    labelText: '隐藏频道',
                    hintText: '*购物*（支持 * 通配）',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('受验证保护（locked）'),
                subtitle: const Text('开启后进入儿童模式需验证 / 家长解锁'),
                value: _locked,
                onChanged: (bool value) => setState(() => _locked = value),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: _save, child: const Text('保存')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
