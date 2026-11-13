import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pscreen_home/features/parental/data/parental_admin_api.dart';
import 'package:pscreen_home/features/parental/domain/parental_share.dart';

/// 「档案共享」页的卡片集合。
///
/// 页面壳只持有共享视图与异步动作，这里全部是无状态 / 局部编辑态 widget，
/// 避免把几百行表单与列表塞进 `ParentalSharePage`。

/// 顶部说明：强调“引用不复制”和“指定家长号才可见”。
class ParentalShareIntroCard extends StatelessWidget {
  const ParentalShareIntroCard({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('引用代替复制', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
              '主本留在原电视，其他电视 / 其他家长只存一条引用；改主本规则一次，'
              '所有引用方自动同步。跨家长分享由档案所有者指定家长号白名单，'
              '只有名单里的家长才看得到、引用得了。',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 6),
            Text(
              '观看时长合并：同一档案在客厅 + 卧室的观看时长按主本累加，例如 30 + 20 = 50 分钟；明细仍分别记录在哪台电视。',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary),
            ),
          ],
        ),
      ),
    );
  }
}

/// 给哪台电视配置（与「我的」页选择的目标一致，点选后由页面壳切换）。
class ParentalShareTargetBar extends StatelessWidget {
  const ParentalShareTargetBar({
    super.key,
    required this.machines,
    required this.currentId,
    required this.onChanged,
  });

  final List<ParentalMachine> machines;
  final String currentId;
  final void Function(ParentalMachine machine) onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('给哪台电视配置', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: machines
              .map(
                (ParentalMachine machine) => ChoiceChip(
                  label: Text(machine.alias.isNotEmpty
                      ? machine.alias
                      : (machine.name.isNotEmpty ? machine.name : machine.id)),
                  avatar: const Icon(Icons.tv_outlined, size: 16),
                  selected: machine.id == currentId,
                  onSelected: (_) => onChanged(machine),
                ),
              )
              .toList(growable: false),
        ),
      ],
    );
  }
}

/// 本台主本档案：可设置“允许哪些家长号引用”。
class ParentalShareMasterCard extends StatefulWidget {
  const ParentalShareMasterCard({
    super.key,
    required this.master,
    this.onSave,
  });

  final ParentalShareMaster master;

  /// 保存白名单（空列表＝取消分享）。异常由页面壳统一提示。
  /// 只读代管（admin）时为 null，按钮禁用并展示「只读代管」。
  final Future<void> Function(List<String> sharedTo)? onSave;

  @override
  State<ParentalShareMasterCard> createState() => _ParentalShareMasterCardState();
}

class _ParentalShareMasterCardState extends State<ParentalShareMasterCard> {
  late final TextEditingController _controller;
  bool _editing = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.master.sharedTo.join(', '));
  }

  @override
  void didUpdateWidget(covariant ParentalShareMasterCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 服务端返回新白名单后回显；用户正在编辑时不打断输入。
    if (!_editing && oldWidget.master.sharedTo != widget.master.sharedTo) {
      _controller.text = widget.master.sharedTo.join(', ');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static List<String> _parseAccounts(String raw) {
    return raw
        .split(RegExp(r'[,，]'))
        .map((String item) => item.trim())
        .where((String item) => item.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }

  Future<void> _save() async {
    if (_saving || widget.onSave == null) return;
    setState(() => _saving = true);
    try {
      await widget.onSave!(_parseAccounts(_controller.text));
      if (!mounted) return;
      setState(() => _editing = false);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final ParentalShareMaster m = widget.master;
    final String sharedText =
        m.sharedTo.isEmpty ? '未分享（仅同家长号跨电视可见）' : '已分享给 ${m.sharedTo.join('、')}';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(m.name, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(
                        '${m.profileModeLabel}${m.dailyLimitMin == null ? '' : ' · 每日 ${m.dailyLimitMin} 分钟'} · $sharedText',
                        style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
                      ),
                    ],
                  ),
                ),
                if (widget.onSave == null)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: const Text('只读代管'),
                    backgroundColor: scheme.surfaceContainerHighest.withValues(alpha: 0.7),
                  )
                else
                  TextButton.icon(
                    onPressed: _saving
                        ? null
                        : () => setState(() {
                            _editing = !_editing;
                            if (_editing) _controller.text = m.sharedTo.join(', ');
                          }),
                    icon: const Icon(Icons.share_outlined, size: 16),
                    label: const Text('分享设置'),
                  ),
              ],
            ),
            if (_editing) ...<Widget>[
              const Divider(height: 12),
              TextField(
                controller: _controller,
                decoration: const InputDecoration(
                  labelText: '可引用的家长号',
                  hintText: '例如：mama88, AA_parent',
                  helperText: '多个用中英文逗号分隔；留空保存＝取消分享',
                  isDense: true,
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => unawaited(_save()),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => setState(() {
                            _editing = false;
                            _controller.text = m.sharedTo.join(', ');
                          }),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 4),
                  FilledButton(
                    onPressed: _saving ? null : () => unawaited(_save()),
                    child: Text(_saving ? '保存中…' : '保存'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 引用进来的档案：来源正常时只读；来源失效保留占位并给“重新选择”。
class ParentalShareImportedCard extends StatelessWidget {
  const ParentalShareImportedCard({
    super.key,
    required this.item,
    this.onCancel,
  });

  final ParentalShareImported item;

  /// 取消引用（不影响主本）。只读代管（admin）时为 null，按钮禁用。
  final Future<void> Function()? onCancel;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool broken = item.isBroken;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: broken ? scheme.errorContainer.withValues(alpha: 0.35) : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    item.name,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: broken ? scheme.error : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    broken
                        ? parentalShareReasonLabel(item.reason)
                        : '引用自 ${item.sourceLabel} · 只读，改规则去主本',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: broken ? scheme.error : scheme.outline,
                    ),
                  ),
                ],
              ),
            ),
            Chip(
              visualDensity: VisualDensity.compact,
              label: Text(broken ? '失效' : '只读'),
              backgroundColor: (broken ? scheme.errorContainer : scheme.secondaryContainer)
                  .withValues(alpha: 0.7),
            ),
            IconButton(
              tooltip: broken ? '重新选择（移除失效占位）' : '取消引用（不影响主本）',
              icon: const Icon(Icons.link_off, size: 20),
              onPressed: onCancel == null ? null : () => unawaited(onCancel!()),
            ),
          ],
        ),
      ),
    );
  }
}

/// 一条可引用候选：同号跨电视 / 其他家长显式分享给我。
class ParentalShareCandidateCard extends StatelessWidget {
  const ParentalShareCandidateCard({
    super.key,
    required this.candidate,
    this.onAdd,
  });

  final ParentalShareCandidate candidate;

  /// 引用该候选到本台。只读代管（admin）时为 null，按钮禁用。
  final Future<void> Function()? onAdd;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(candidate.name, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    '来自 ${candidate.machineName}'
                    '${candidate.dailyLimitMin == null ? '' : ' · 每日 ${candidate.dailyLimitMin} 分钟'}',
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
                  ),
                  if (!candidate.isTv)
                    Text('来源不是电视设备，请确认来源已上报设备类型',
                        style: theme.textTheme.bodySmall?.copyWith(color: scheme.error)),
                ],
              ),
            ),
            FilledButton.tonal(
              style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: onAdd == null ? null : () => unawaited(onAdd!()),
              child: const Text('＋ 引用'),
            ),
          ],
        ),
      ),
    );
  }
}
