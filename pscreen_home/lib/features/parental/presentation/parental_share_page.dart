import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pscreen_home/core/server/account_session.dart';
import 'package:pscreen_home/features/parental/data/parental_admin_api.dart';
import 'package:pscreen_home/features/parental/domain/parental_share.dart';
import 'package:pscreen_home/features/parental/presentation/parental_common.dart';
import 'package:pscreen_home/features/parental/presentation/parental_share_cards.dart';

/// 「我的 → 档案共享」下钻页。
///
/// 状态壳只做三件事：持有当前目标电视、持有共享视图、把写操作委托给
/// [ParentalActions]。列表卡片全部外置在 `parental_share_cards.dart`，
/// 遵循“不往一个文件堆几千行”的约定。
class ParentalSharePage extends StatefulWidget {
  const ParentalSharePage({
    super.key,
    required this.machine,
    required this.machines,
    required this.actions,
    this.initialView,
  });

  /// 进入页面时的目标电视（通常是「我的」页当前选中的那台）。
  final ParentalMachine machine;

  /// 当前家长可见的全部电视，用于页内切换配置目标。
  final List<ParentalMachine> machines;

  final ParentalActions actions;

  /// overview 已经预展开的共享视图；有值则首屏零请求。
  final ParentalShareView? initialView;

  @override
  State<ParentalSharePage> createState() => _ParentalSharePageState();
}

/// admin 只读代管：所有写入口禁用（D-03，与服务端 requireParentWriter 对应）。
bool _isReadOnly() => !AccountSession.isParent;

class _ParentalSharePageState extends State<ParentalSharePage> {
  late ParentalMachine _machine;
  late ParentalShareView _view;
  bool _loading = true;
  String? _error;

  /// 父页面在写操作后会重建 machines 列表；按 id 找回最新实例，
  /// 避免把旧 alias / shareView 再传回服务端。
  ParentalMachine get _latestMachine {
    for (final ParentalMachine item in widget.machines) {
      if (item.id == _machine.id) return item;
    }
    return _machine;
  }

  @override
  void initState() {
    super.initState();
    _machine = widget.machine;
    _view = widget.initialView ?? ParentalShareView.empty;
    _loading = widget.initialView == null;
    if (_loading) unawaited(_reload());
  }

  Future<void> _reload() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ParentalShareView view = await widget.actions.loadShareView(_latestMachine);
      if (!mounted) return;
      setState(() => _view = view);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 统一包装三个写操作：成功替换视图，失败保留旧视图并明确提示。
  Future<void> _mutate(
    Future<ParentalShareView> Function() operation, {
    required String success,
  }) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ParentalShareView view = await operation();
      if (!mounted) return;
      setState(() {
        _view = view;
        _machine = _latestMachine.copyWith(shareView: view);
      });
      _hint(success);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
      _hint('$success失败：$error', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _hint(String message, {bool error = false}) {
    if (!mounted) return;
    final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: error ? Theme.of(context).colorScheme.error : null,
        ),
      );
  }

  Future<void> _switchTarget(ParentalMachine machine) async {
    if (machine.id == _machine.id) return;
    widget.actions.selectDevice(machine);
    if (!mounted) return;
    setState(() {
      _machine = machine;
      _view = machine.shareView ?? ParentalShareView.empty;
      _loading = machine.shareView == null;
      _error = null;
    });
    if (machine.shareView == null) await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<ParentalShareCandidate> sameAccount = _view.candidates
        .where((ParentalShareCandidate item) => item.isSameAccount)
        .toList(growable: false);
    final List<ParentalShareCandidate> sharedToMe = _view.candidates
        .where((ParentalShareCandidate item) => !item.isSameAccount)
        .toList(growable: false);

    return Scaffold(
      appBar: AppBar(title: const Text('档案共享')),
      body: Stack(
        children: <Widget>[
          RefreshIndicator(
            onRefresh: _reload,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              physics: const AlwaysScrollableScrollPhysics(),
              children: <Widget>[
                if (_isReadOnly())
                  _ReadOnlyBanner(),
                const ParentalShareIntroCard(),
                const SizedBox(height: 14),
                if (widget.machines.length > 1)
                  ParentalShareTargetBar(
                    machines: widget.machines,
                    currentId: _machine.id,
                    onChanged: (ParentalMachine machine) => unawaited(_switchTarget(machine)),
                  )
                else
                  Text(
                    '当前电视：${_machine.alias.isNotEmpty ? _machine.alias : _machine.name}',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                  ),
                const SizedBox(height: 14),
                _SectionHeader(
                  title: '本台档案 · 主本',
                  hint: '点「分享设置」指定可引用的家长号；留空＝不分享',
                ),
                if (_view.masters.isEmpty)
                  _EmptyHint(text: '本台还没有主本档案，请到「规则」页添加。')
                else
                  for (final ParentalShareMaster master in _view.masters)
                    ParentalShareMasterCard(
                      key: ValueKey<String>('master:${master.id}:${master.sharedTo.join(',')}'),
                      master: master,
                      onSave: _isReadOnly()
                          ? null
                          : (List<String> sharedTo) => _mutate(
                            () => widget.actions.setSharedTo(
                              _latestMachine,
                              master,
                              sharedTo,
                            ),
                            success: sharedTo.isEmpty ? '已取消分享' : '已分享给 ${sharedTo.join('、')}',
                          ),
                    ),
                const SizedBox(height: 6),
                _SectionHeader(
                  title: '引用进来的档案（主本在别处）',
                  hint: '只读；来源被删/解绑/取消分享会标失效并保留占位',
                ),
                if (_view.imported.isEmpty)
                  const _EmptyHint(text: '本台还没有引用其他电视的档案。')
                else
                  for (final ParentalShareImported item in _view.imported)
                    ParentalShareImportedCard(
                      key: ValueKey<String>('imported:${item.refId}'),
                      item: item,
                      onCancel: _isReadOnly()
                          ? null
                          : () => _mutate(
                            () => widget.actions.cancelSharedRef(_latestMachine, item),
                            success: '已取消引用（不影响主本）',
                          ),
                    ),
                const SizedBox(height: 6),
                _SectionHeader(
                  title: '同一家长号 · 跨电视引用',
                  hint: '同一个家长号名下的其他电视，默认可见，无需对方勾选',
                ),
                if (sameAccount.isEmpty)
                  const _EmptyHint(text: '同账号下暂无可引用档案。')
                else
                  for (final ParentalShareCandidate item in sameAccount)
                    ParentalShareCandidateCard(
                      key: ValueKey<String>('candidate:${item.machineId}:${item.childId}'),
                      candidate: item,
                      onAdd: _isReadOnly()
                          ? null
                          : () => _mutate(
                            () => widget.actions.addSharedRef(_latestMachine, item),
                            success: '已引用「${item.name}」，主本在 ${item.machineName}',
                          ),
                    ),
                const SizedBox(height: 6),
                _SectionHeader(
                  title: '其他家长分享给我',
                  hint: '只有对方在主本档案上把你加进分享名单才出现在这里',
                ),
                if (sharedToMe.isEmpty)
                  const _EmptyHint(text: '暂时没有其他家长指定分享给你的档案。')
                else
                  for (final ParentalShareCandidate item in sharedToMe)
                    ParentalShareCandidateCard(
                      key: ValueKey<String>('candidate:${item.machineId}:${item.childId}'),
                      candidate: item,
                      onAdd: _isReadOnly()
                          ? null
                          : () => _mutate(
                            () => widget.actions.addSharedRef(_latestMachine, item),
                            success: '已引用「${item.name}」，主本在 ${item.machineName}',
                          ),
                    ),
              ],
            ),
          ),
          if (_error != null)
            Positioned(
              left: 16,
              right: 16,
              top: 4,
              child: Card(
                color: theme.colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          '共享视图加载失败：$_error',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      IconButton(
                        tooltip: '重试',
                        icon: const Icon(Icons.refresh, size: 18),
                        onPressed: () => unawaited(_reload()),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_loading)
            const Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: LinearProgressIndicator(minHeight: 2),
            ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.hint});

  final String title;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          Text(hint, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
        ),
      );
}

/// admin 只读代管提示条：明确本页所有写入口被禁用、需由家长号操作。
class _ReadOnlyBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.visibility_outlined, size: 18, color: scheme.outline),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '只读代管：分享设置、引用与取消均不可在此修改，请使用家长号操作。',
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
            ),
          ),
        ],
      ),
    );
  }
}
