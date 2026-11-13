import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pscreen_home/features/parental/application/parental_telemetry.dart';
import 'package:pscreen_home/features/parental/data/parental_admin_api.dart';
import 'package:pscreen_home/features/parental/domain/parental_config.dart';
import 'package:pscreen_home/features/parental/presentation/parental_common.dart';

/// 题库分享（CR-01）：替代旧的「档案共享」三态。
///
/// 两部分：
/// 1. 分享出（我的题库授权给谁）：把本儿童题库的 `sharedTo` 设为可导入的家长号，
///    只授权账号、不传 childId（S1 定稿）。
/// 2. 引用入（导入他人分享给我的题库）：从「分享给我的题库」列表一键复制副本到
///    我自己的某个儿童档案（Q1 复制副本，不引用、不共账；Q2 选择挂到我的 childId）。
///
/// 不展示任何使用统计（Q3 口径：严禁含时长 / 观看记录 / 孩子姓名）。
class ParentalQuizShareSheet extends StatefulWidget {
  const ParentalQuizShareSheet({
    super.key,
    required this.api,
    required this.child,
  });

  final ParentalAdminApi api;
  final FamilyChild child;

  static Future<void> show(
    BuildContext context, {
    required ParentalAdminApi api,
    required FamilyChild child,
  }) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (BuildContext context) => ParentalQuizShareSheet(
          api: api,
          child: child,
        ),
      );

  @override
  State<ParentalQuizShareSheet> createState() => _ParentalQuizShareSheetState();
}

class _ParentalQuizShareSheetState extends State<ParentalQuizShareSheet> {
  final TextEditingController _account = TextEditingController();
  List<String> _sharedTo = const <String>[];
  List<FamilyChild> _myChildren = const <FamilyChild>[];
  List<SharedQuizInfo> _sharedToMe = const <SharedQuizInfo>[];
  bool _loading = true;
  bool _savingShare = false;

  /// D-01：题库实体版本号（来自家庭档案列表的 `quizRevision`）。
  int _quizRevision = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _sharedTo = List<String>.from(widget.child.sharedTo);
    _quizRevision = widget.child.quizRevision;
    unawaited(_load());
  }

  @override
  void dispose() {
    _account.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final List<FamilyChild> children = await widget.api.fetchFamilyChildren();
      if (!mounted) return;
      List<SharedQuizInfo> sharedToMe = const <SharedQuizInfo>[];
      try {
        sharedToMe = await widget.api.fetchSharedToMeQuizzes();
      } catch (_) {
        // 服务端若尚未部署 shared-to-me 端点，导入区留空，不影响「分享出」功能。
      }
      if (!mounted) return;
      // 冲突放弃 / 重新进入时，用服务端最新值校正本档案的分享名单与版本。
      FamilyChild? latest;
      for (final FamilyChild c in children) {
        if (c.id == widget.child.id) {
          latest = c;
          break;
        }
      }
      setState(() {
        _myChildren = children;
        _sharedToMe = sharedToMe;
        if (latest != null) {
          _sharedTo = List<String>.from(latest.sharedTo);
          _quizRevision = latest.quizRevision;
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _saveShare() async {
    if (_savingShare) return;
    setState(() => _savingShare = true);
    final List<String> mine = List<String>.from(_sharedTo);
    try {
      final List<String> saved = await widget.api.setQuizShare(
        widget.child.id,
        mine,
        baseRevision: _quizRevision,
      );
      if (!mounted) return;
      ParentalTelemetry.quizShare(ok: true);
      setState(() {
        _sharedTo = saved;
        _quizRevision += 1;
        _savingShare = false;
      });
      _toast('已保存分享范围（${saved.length} 个家长号）');
    } on ParentalConflictException catch (e) {
      if (!mounted) return;
      setState(() => _savingShare = false);
      final ParentalConflictChoice choice = await showParentalConflictDialog(
        context,
        title: '题库分享设置已被其他设备修改',
        message: '${e.message}\n\n可以查看差异，或用你当前的名单覆盖服务端最新设置。',
        mine: <String, dynamic>{'sharedTo': mine},
        theirs: e.current,
      );
      ParentalTelemetry.conflict('quizShare', choice.name);
      if (!mounted) return;
      if (choice == ParentalConflictChoice.overwrite) {
        final int serverRevision = (e.current?['revision'] as num?)?.toInt() ?? 0;
        setState(() => _savingShare = true);
        try {
          final List<String> saved = await widget.api.setQuizShare(
            widget.child.id,
            mine,
            baseRevision: serverRevision,
          );
          if (!mounted) return;
          ParentalTelemetry.quizShare(ok: true);
          setState(() {
            _sharedTo = saved;
            _quizRevision = serverRevision + 1;
            _savingShare = false;
          });
          _toast('已保存分享范围（${saved.length} 个家长号）');
        } catch (error) {
          if (!mounted) return;
          ParentalTelemetry.quizShare(ok: false);
          setState(() => _savingShare = false);
          _toast('覆盖失败：$error', error: true);
        }
        return;
      }
      // 放弃：回读家庭档案以恢复服务端最新名单。
      await _load();
    } catch (e) {
      if (!mounted) return;
      ParentalTelemetry.quizShare(ok: false);
      setState(() => _savingShare = false);
      _toast('保存失败：$e', error: true);
    }
  }

  void _addAccount() {
    final String v = _account.text.trim();
    if (v.isEmpty) return;
    if (_sharedTo.contains(v)) {
      _account.clear();
      return;
    }
    setState(() {
      _sharedTo = <String>[..._sharedTo, v];
      _account.clear();
    });
  }

  void _removeAccount(String v) =>
      setState(() => _sharedTo = _sharedTo.where((String x) => x != v).toList());

  Future<void> _import(SharedQuizInfo info, String targetChildId) async {
    try {
      await widget.api.importQuizCopy(
        targetChildId: targetChildId,
        sourceChildId: info.sourceChildId,
        sourceAccount: info.sourceAccount,
      );
      ParentalTelemetry.quizShare(ok: true, action: 'import');
      if (!mounted) return;
      _toast('已复制「${info.childName}」的题库到本档案');
      await _load();
    } catch (e) {
      ParentalTelemetry.quizShare(ok: false, action: 'import');
      if (!mounted) return;
      _toast('导入失败：$e', error: true);
    }
  }

  void _toast(String message, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? Theme.of(context).colorScheme.errorContainer : null,
      ));
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '题库分享 · ${widget.child.name}',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: '关闭',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_error!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.error)),
            ),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                children: <Widget>[
                    _SectionTitle(icon: Icons.upload_outlined, text: '把我的题库分享给'),
                    const SizedBox(height: 8),
                    Text(
                      '填写家长号即授权对方「导入副本」；留空表示不分享。'
                      '仅授权账号，不传儿童档案（跨家庭只分享题库）。',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.outline),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: <Widget>[
                        ..._sharedTo.map(
                          (String a) => Chip(
                            label: Text(a),
                            deleteIcon: const Icon(Icons.cancel, size: 16),
                            onDeleted: () => _removeAccount(a),
                          ),
                        ),
                        if (_sharedTo.isEmpty)
                          Text('尚未分享给任何人',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: scheme.outline)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: TextField(
                            controller: _account,
                            decoration: const InputDecoration(
                              labelText: '家长号',
                              hintText: '如 grandpa99',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onSubmitted: (_) => _addAccount(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.tonal(
                          onPressed: _savingShare ? null : _addAccount,
                          child: const Text('添加'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: _savingShare ? null : () => unawaited(_saveShare()),
                          child: _savingShare
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('保存'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _SectionTitle(icon: Icons.download_outlined, text: '引用他人分享给我的题库'),
                    const SizedBox(height: 8),
                    Text(
                      '以下是其他家长分享给你、且授权你导入的题库；一键复制成本档案的'
                      '独立副本（不引用、不共账，你后续可独立编辑）。不显示任何使用统计。',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.outline),
                    ),
                    const SizedBox(height: 10),
                    if (_sharedToMe.isEmpty)
                      Text('没有分享给你的题库',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: scheme.outline))
                    else
                      ..._sharedToMe.map(
                        (SharedQuizInfo info) => _ImportRow(
                          info: info,
                          myChildren: _myChildren,
                          defaultTarget: widget.child.id,
                          onImport: _import,
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
        children: <Widget>[
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            text,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      );
}

class _ImportRow extends StatefulWidget {
  const _ImportRow({
    required this.info,
    required this.myChildren,
    required this.defaultTarget,
    required this.onImport,
  });

  final SharedQuizInfo info;
  final List<FamilyChild> myChildren;
  final String defaultTarget;
  final Future<void> Function(SharedQuizInfo info, String targetChildId) onImport;

  @override
  State<_ImportRow> createState() => _ImportRowState();
}

class _ImportRowState extends State<_ImportRow> {
  late String _target;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _target = widget.defaultTarget;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool canImport = widget.myChildren.isNotEmpty;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('${widget.info.childName} · ${widget.info.questionCount} 题',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text('来自家长号：${widget.info.sourceAccount}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline)),
            const SizedBox(height: 10),
            if (!canImport)
              Text('你还没有儿童档案，无法导入',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error))
            else
              Row(
                children: <Widget>[
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _target,
                      decoration: const InputDecoration(
                        labelText: '导入到我的档案',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: widget.myChildren
                          .map((FamilyChild c) => DropdownMenuItem<String>(
                                value: c.id,
                                child: Text(c.name),
                              ))
                          .toList(growable: false),
                      onChanged: (String? v) => setState(() => _target = v ?? _target),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : () => unawaited(_doImport()),
                    child: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('导入副本'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _doImport() async {
    setState(() => _busy = true);
    try {
      await widget.onImport(widget.info, _target);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
