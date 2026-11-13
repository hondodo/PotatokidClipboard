import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:pscreen_home/features/parental/data/parental_admin_api.dart';
import 'package:pscreen_home/features/parental/domain/parental_config.dart';
import 'package:pscreen_home/features/parental/presentation/parental_common.dart';
import 'package:pscreen_home/features/parental/presentation/parental_quiz_editor.dart';
import 'package:pscreen_home/features/parental/presentation/parental_quiz_share_sheet.dart';
import 'package:pscreen_screen/core/parental/child_avatar.dart';

/// 家庭档案中心（Task 32 / D-02 家庭级主档案的家长端主入口）。
///
/// 儿童档案按 `childId` 全局唯一、规则（限额 / 禁看时段 / 黑白名单 / 档位）全部
/// 归家庭主档案，电视端只按「分配表」投影已启用的档案（S2 同规则、不逐台改）。
/// 本页负责：全局儿童档案的增删改、把档案分配到哪些电视、以及题库入口。
///
/// 与旧「档案共享」页不再相关：CR-01 后跨家庭只分享题库（见 [ParentalQuizShareSheet]）。
class ParentalFamilyPage extends StatefulWidget {
  const ParentalFamilyPage({
    super.key,
    required this.machines,
    required this.myAccount,
    this.onChanged,
    this.embedded = false,
  });

  /// 是否作为「孩子」Tab 内嵌（不显示自己的 AppBar，由外层导航壳承载标题）。
  final bool embedded;

  /// 当前家长可见的设备清单（用于解析电视名、挑选题库编辑用的电视）。
  final List<ParentalMachine> machines;

  /// 家长号（管理登录身份，用于筛选「我管理的电视」）。
  final String myAccount;

  /// 档案 / 分配变更后通知外层刷新（如重新拉取配置让电视生效）。
  final VoidCallback? onChanged;

  @override
  State<ParentalFamilyPage> createState() => _ParentalFamilyPageState();
}

class _ParentalFamilyPageState extends State<ParentalFamilyPage> {
  final ParentalAdminApi _api = const ParentalAdminApi();
  List<FamilyChild> _children = const <FamilyChild>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final List<FamilyChild> list = await _api.fetchFamilyChildren();
      if (!mounted) return;
      setState(() {
        _children = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  /// 当前家长能管理的电视（kind == tv 且 parents 含本账号）。
  List<ParentalMachine> get _managedTvs => widget.machines
      .where((ParentalMachine m) =>
          (m.kind == 'tv') && m.parents.contains(widget.myAccount))
      .toList(growable: false);

  Future<void> _notifyChanged() async {
    widget.onChanged?.call();
  }

  Future<void> _openEditor([FamilyChild? child]) async {
    final FamilyChild? saved = await FamilyChildEditorSheet.show(
      context,
      initial: child,
      existingIds: _children.map((FamilyChild c) => c.id).toList(growable: false),
      managedTvs: _managedTvs,
    );
    if (saved == null || !mounted) return;
    setState(() => _loading = true);
    final int? baseRevision = child?.revision;
    try {
      await _api.saveFamilyChild(saved.toJson(), baseRevision: baseRevision);
      if (!mounted) return;
      await _load();
      await _notifyChanged();
    } on ParentalConflictException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      await _showConflictAndReload(e);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _toast('保存失败：$e', error: true);
    }
  }

  /// D-01：冲突时提示「已被其他设备修改」，并回读最新数据，避免静默覆盖。
  Future<void> _showConflictAndReload(ParentalConflictException e) async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('档案已被其他设备修改'),
        content: Text('${e.message}\n\n已为你刷新为服务端最新内容，请确认后再修改。'),
        actions: <Widget>[
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('好，看最新内容'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    await _load();
    await _notifyChanged();
  }

  Future<void> _delete(FamilyChild child) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('删除儿童档案'),
        content: Text(
          '确定删除「${child.name}」的家庭档案吗？\n\n'
          '该档案会从所有电视移除（与解绑不同，档案本身被删除、题库也一并删除）。'
          '此操作不可恢复。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除档案'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _loading = true);
    try {
      await _api.deleteFamilyChild(child.id);
      if (!mounted) return;
      await _load();
      await _notifyChanged();
      _toast('已删除「${child.name}」');
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _toast('删除失败：$e', error: true);
    }
  }

  Future<void> _openAssignment(FamilyChild child) async {
    final bool? changed = await _AssignmentSheet.show(
      context,
      api: _api,
      child: child,
      tvs: _managedTvs,
    );
    if (changed != true || !mounted) return;
    await _load();
    await _notifyChanged();
  }

  /// 题库编辑：复用既有 [ParentalQuizEditorSheet]，deviceId 用「我管理且已分配本档案」
  /// 的电视；若都没有则退而用任意我管理的电视（服务端按 childId 分库，deviceId 仅作权限校验）。
  Future<void> _openQuiz(FamilyChild child) async {
    final List<ParentalMachine> assigned = _managedTvs
        .where((ParentalMachine m) =>
            child.assignedTo.any((FamilyTvRef r) => r.id == m.id))
        .toList(growable: false);
    final ParentalMachine? tv =
        assigned.isNotEmpty ? assigned.first : _managedTvs.firstOrNull;
    if (tv == null) {
      _toast('没有可管理的电视，请先在「我的电视」绑定一台电视', error: true);
      return;
    }
    await ParentalQuizEditorSheet.show(
      context,
      deviceId: tv.id,
      child: ParentalChild(id: child.id, name: child.name),
    );
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
    final Widget content = _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
            ? _CenterHint(
                icon: Icons.error_outline,
                text: _error!,
                action: FilledButton.icon(
                  onPressed: () => unawaited(_load()),
                  icon: const Icon(Icons.refresh),
                  label: const Text('重试'),
                ),
              )
            : _children.isEmpty
                ? _CenterHint(
                    icon: Icons.family_restroom_outlined,
                    text: '还没有家庭儿童档案。\n添加后，再到「分配到电视」让指定电视生效。',
                    action: FilledButton.icon(
                      onPressed: () => unawaited(_openEditor()),
                      icon: const Icon(Icons.add),
                      label: const Text('添加儿童档案'),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                    itemCount: _children.length,
                    separatorBuilder: (BuildContext context, int index) =>
                        const SizedBox(height: 12),
                    itemBuilder: (BuildContext context, int index) =>
                        _FamilyChildCard(
                      child: _children[index],
                      tvs: _managedTvs,
                      onEdit: () => unawaited(_openEditor(_children[index])),
                      onDelete: () => unawaited(_delete(_children[index])),
                      onAssign: () => unawaited(_openAssignment(_children[index])),
                      onQuiz: () => unawaited(_openQuiz(_children[index])),
                      onShareQuiz: () => unawaited(_openQuizShare(_children[index])),
                    ),
                  );
    final Widget fab = FloatingActionButton.extended(
      icon: const Icon(Icons.add),
      label: const Text('添加儿童档案'),
      onPressed: () => unawaited(_openEditor()),
    );
    if (widget.embedded) {
      return Scaffold(floatingActionButton: fab, body: content);
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('家庭档案'),
        actions: <Widget>[
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: () => unawaited(_load()),
          ),
        ],
      ),
      floatingActionButton: fab,
      body: content,
    );
  }

  Future<void> _openQuizShare(FamilyChild child) async {
    await ParentalQuizShareSheet.show(context, api: _api, child: child);
  }
}

/// 家庭档案卡片：展示规则摘要 + 分配到的电视，提供编辑 / 删除 / 分配 / 题库 / 分享题库。
class _FamilyChildCard extends StatelessWidget {
  const _FamilyChildCard({
    required this.child,
    required this.tvs,
    required this.onEdit,
    required this.onDelete,
    required this.onAssign,
    required this.onQuiz,
    required this.onShareQuiz,
  });

  final FamilyChild child;
  final List<ParentalMachine> tvs;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onAssign;
  final VoidCallback onQuiz;
  final VoidCallback onShareQuiz;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final List<String> limitParts = <String>[
      if (child.dailyLimitMin > 0) '每日 ${child.dailyLimitMin} 分',
      if (child.sessionLimitMin > 0) '单次 ${child.sessionLimitMin} 分',
      if (child.bedtimeStart.isNotEmpty && child.bedtimeEnd.isNotEmpty)
        '禁看 ${child.bedtimeStart}-${child.bedtimeEnd}',
    ];
    String nameOf(String id) {
      final ParentalMachine? m =
          tvs.where((ParentalMachine x) => x.id == id).firstOrNull;
      return m == null ? id : parentalTvName(m);
    }
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ListTile(
            leading: SizedBox(
              width: 40,
              height: 40,
              child: ClipOval(
                child: ChildAvatarWidget(
                  avatar: child.avatarId,
                  fallback: Container(
                    color: scheme.primaryContainer,
                    alignment: Alignment.center,
                    child: Text(
                      child.name.isNotEmpty ? child.name[0] : '?',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            title: Row(
              children: <Widget>[
                Expanded(child: Text(child.name)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: child.isStrict
                        ? scheme.errorContainer
                        : scheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    child.profileModeLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: child.isStrict
                          ? scheme.onErrorContainer
                          : scheme.onSecondaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            subtitle: Text(
              <String>[
                if (child.age != null) '${child.age} 岁',
                if (limitParts.isNotEmpty) limitParts.join(' · '),
                if (child.locked) '已加密锁',
              ].join(' · '),
            ),
            trailing: PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (String value) {
                switch (value) {
                  case 'edit':
                    onEdit();
                  case 'delete':
                    onDelete();
                }
              },
              itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                const PopupMenuItem<String>(
                  value: 'edit',
                  child: ListTile(
                    leading: Icon(Icons.edit_outlined),
                    title: Text('编辑档案'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'delete',
                  child: ListTile(
                    leading: Icon(Icons.delete_outline),
                    title: Text('删除档案'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '分配到电视',
                  style: theme.textTheme.labelSmall?.copyWith(color: scheme.outline),
                ),
                const SizedBox(height: 6),
                if (child.assignedTo.isEmpty)
                  Text(
                    '尚未分配到任何电视，点击「分配」让指定电视生效',
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
                  )
                else
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: child.assignedTo
                        .map((FamilyTvRef r) => Chip(
                              visualDensity: VisualDensity.compact,
                              label: Text(nameOf(r.id)),
                            ))
                        .toList(growable: false),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Wrap(
              spacing: 4,
              runSpacing: 0,
              children: <Widget>[
                TextButton.icon(
                  onPressed: onAssign,
                  icon: const Icon(Icons.tv_outlined, size: 18),
                  label: const Text('分配电视'),
                ),
                TextButton.icon(
                  onPressed: onQuiz,
                  icon: const Icon(Icons.quiz_outlined, size: 18),
                  label: const Text('题库'),
                ),
                TextButton.icon(
                  onPressed: onShareQuiz,
                  icon: const Icon(Icons.share_outlined, size: 18),
                  label: Text(child.sharedTo.isEmpty
                      ? '分享题库'
                      : '分享题库(${child.sharedTo.length})'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 居中提示 + 操作按钮（空态 / 错误态复用）。
class _CenterHint extends StatelessWidget {
  const _CenterHint({
    required this.icon,
    required this.text,
    this.action,
  });

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: 12),
              Text(
                text,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Theme.of(context).colorScheme.outline),
              ),
              if (action != null) ...<Widget>[
                const SizedBox(height: 16),
                action!,
              ],
            ],
          ),
        ),
      );
}

/// 全局儿童档案编辑页（新增 / 编辑共用）。
///
/// 字段对齐服务端 `familyStore` 的 FamilyChild：姓名 / 年龄 / 档位 / 限额 /
/// 禁看时段 / 加密锁 / 黑白名单。保存时整份 upsert（按 childId 覆盖）。
class FamilyChildEditorSheet extends StatefulWidget {
  const FamilyChildEditorSheet({
    super.key,
    this.initial,
    required this.existingIds,
    required this.managedTvs,
  });

  final FamilyChild? initial;
  final List<String> existingIds;

  /// 我管理的电视清单：上传头像需要一个受管理的 TV deviceId 作为素材归属桶
  /// （服务端按家长维度合并所有 TV 的素材，故任意一台即可）。
  final List<ParentalMachine> managedTvs;

  static Future<FamilyChild?> show(
    BuildContext context, {
    FamilyChild? initial,
    required List<String> existingIds,
    required List<ParentalMachine> managedTvs,
  }) =>
      showModalBottomSheet<FamilyChild?>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (BuildContext context) => FamilyChildEditorSheet(
          initial: initial,
          existingIds: existingIds,
          managedTvs: managedTvs,
        ),
      );

  @override
  State<FamilyChildEditorSheet> createState() => _FamilyChildEditorSheetState();
}

class _FamilyChildEditorSheetState extends State<FamilyChildEditorSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _age = TextEditingController();
  final TextEditingController _daily = TextEditingController();
  final TextEditingController _session = TextEditingController();
  final TextEditingController _bedStart = TextEditingController();
  final TextEditingController _bedEnd = TextEditingController();
  final TextEditingController _blacklist = TextEditingController();
  String _profileMode = 'mild';
  bool _locked = false;
  String? _idError;

  /// 当前选中的头像值（`preset:xxx` / `http(s)://...` / null）。
  String? _avatar;

  /// 已上传到 app_server 的素材（从服务端拉取，按家庭维度合并去重）。
  List<AvatarItem> _uploadedAvatars = const <AvatarItem>[];

  /// 预设头像 key 列表（`preset:` 前缀的值）。
  final List<String> _presetAvatars = kPresetAvatarKeys;

  /// 上传中状态：null = 空闲；有值 = 上传中（本地预览 bytes）。
  Uint8List? _uploadingPreviewBytes;
  double _uploadingProgress = 0; // 0..1

  @override
  void initState() {
    super.initState();
    final FamilyChild? c = widget.initial;
    if (c != null) {
      _name.text = c.name;
      _age.text = c.age == null ? '' : '${c.age}';
      _daily.text = c.dailyLimitMin == 0 ? '' : '${c.dailyLimitMin}';
      _session.text = c.sessionLimitMin == 0 ? '' : '${c.sessionLimitMin}';
      _bedStart.text = c.bedtimeStart;
      _bedEnd.text = c.bedtimeEnd;
      _blacklist.text = c.blacklist.join('，');
      _profileMode = c.profileMode;
      _locked = c.locked;
    }
    _avatar = c?.avatarId;
    unawaited(_loadUploadedAvatars());
  }

  @override
  void dispose() {
    _name.dispose();
    _age.dispose();
    _daily.dispose();
    _session.dispose();
    _bedStart.dispose();
    _bedEnd.dispose();
    _blacklist.dispose();
    super.dispose();
  }

  void _toast(String message, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor:
            error ? Theme.of(context).colorScheme.errorContainer : null,
      ));
  }

  Future<void> _loadUploadedAvatars() async {
    try {
      final List<AvatarItem> list = await const ParentalAdminApi().listAvatars();
      if (!mounted) return;
      setState(() => _uploadedAvatars = list);
    } catch (_) {
      // 拉不到就算了；预设头像仍然可用，用户也能临时上传。
    }
  }

  Future<void> _pickAndUploadAvatar() async {
    if (_uploadingPreviewBytes != null) return; // 防重入
    final ParentalMachine? tv = widget.managedTvs.firstOrNull;
    if (tv == null) {
      _toast('需先绑定并管理一台电视后才能上传头像', error: true);
      return;
    }
    final PlatformFile? file = await FilePicker.pickFile(type: FileType.image);
    if (file == null || !mounted) return;
    try {
      final Uint8List? raw = await file.readAsBytes();
      if (raw == null) throw Exception('无法读取图片');
      final img.Image? decoded = img.decodeImage(raw);
      if (decoded == null) throw Exception('图片格式无法识别');
      final int side =
          decoded.width < decoded.height ? decoded.width : decoded.height;
      final int offX = (decoded.width - side) ~/ 2;
      final int offY = (decoded.height - side) ~/ 2;
      final img.Image cropped = img.copyCrop(
        decoded,
        x: offX,
        y: offY,
        width: side,
        height: side,
      );
      final img.Image resized =
          img.copyResize(cropped, width: 256, height: 256);
      final Uint8List encoded = Uint8List.fromList(img.encodePng(resized));
      if (!mounted) return;
      // 置上传中状态（显示本地预览 + 半透明进度条上涨）。
      setState(() {
        _uploadingPreviewBytes = encoded;
        _uploadingProgress = 0;
      });
      // 真实进度回调：total 可能为 -1（没给 content-length），回落到本地
      // 估算的 base64 JSON 大小做 total（足够精确）。
      final int estimatedTotal = base64Encode(encoded).length + 200;
      final String url = await const ParentalAdminApi().uploadAvatar(
        tv.id,
        bytes: encoded,
        onSendProgress: (int sent, int total) {
          if (!mounted) return;
          final int denom = (total > 0 ? total : estimatedTotal);
          final double p = (sent / denom).clamp(0.0, 1.0);
          if ((p - _uploadingProgress).abs() < 0.025) return; // 节流
          setState(() => _uploadingProgress = p);
        },
      );
      if (!mounted) return;
      setState(() {
        _uploadingProgress = 1.0;
        _avatar = url;
        _uploadedAvatars = <AvatarItem>[
          AvatarItem(
            id: 'uploaded_${DateTime.now().millisecondsSinceEpoch}',
            url: url,
            sha256: '',
            mime: 'image/png',
            size: encoded.length,
          ),
          ..._uploadedAvatars,
        ];
      });
      await Future<void>.delayed(const Duration(milliseconds: 220));
      if (!mounted) return;
      setState(() {
        _uploadingPreviewBytes = null;
        _uploadingProgress = 0;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _uploadingPreviewBytes = null;
          _uploadingProgress = 0;
        });
        _toast('头像上传失败：$error', error: true);
      }
    }
  }

  bool _isSelectedUploaded(String url) => _avatar == url;
  bool _isSelectedPreset(String key) => _avatar == 'preset:$key';

  Future<void> _confirmDeleteAvatar(AvatarItem item) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('删除头像？'),
        content: const Text(
          '删除后这个素材在所有设备上都不再显示，但已使用它的档案仍然引用着它。'
          '档案里的头像需要重新选择一次才会换掉。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await const ParentalAdminApi().deleteAvatar(item.id);
      if (!mounted) return;
      setState(() {
        _uploadedAvatars = _uploadedAvatars
            .where((AvatarItem a) => a.id != item.id)
            .toList(growable: false);
        if (_avatar == item.url) _avatar = null;
      });
    } catch (error) {
      if (mounted) _toast('删除失败：$error', error: true);
    }
  }

  String _newId() {
    final String base = _name.text.trim();
    if (base.isEmpty) return '';
    return 'child_${base.hashCode.abs().toRadixString(36)}';
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final String name = _name.text.trim();
    final String id = widget.initial?.id ?? _newId();
    if (id.isEmpty) {
      setState(() => _idError = '请先填写姓名');
      return;
    }
    if (widget.initial == null && widget.existingIds.contains(id)) {
      setState(() => _idError = '已存在同名档案，请使用不同姓名或先删除旧档案');
      return;
    }
    final FamilyChild result = FamilyChild(
      id: id,
      name: name,
      age: int.tryParse(_age.text.trim()),
      avatarId: _avatar,
      profileMode: _profileMode,
      dailyLimitMin: int.tryParse(_daily.text.trim()) ?? 0,
      sessionLimitMin: int.tryParse(_session.text.trim()) ?? 0,
      bedtimeStart: _bedStart.text.trim(),
      bedtimeEnd: _bedEnd.text.trim(),
      blacklist: _blacklist.text
          .split(RegExp(r'[，,、\s]+'))
          .map((String s) => s.trim())
          .where((String s) => s.isNotEmpty)
          .toList(growable: false),
      locked: _locked,
    );
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Text(
                    widget.initial == null ? '添加儿童档案' : '编辑儿童档案',
                    style: theme.textTheme.titleMedium,
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                  FilledButton(onPressed: _save, child: const Text('保存')),
                ],
              ),
              const SizedBox(height: 12),
              Text('头像', style: theme.textTheme.bodySmall),
              const SizedBox(height: 6),
              SizedBox(
                height: 72,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: 2 + _uploadedAvatars.length + _presetAvatars.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (BuildContext context, int index) {
                    if (index == 0) {
                      final bool uploading = _uploadingPreviewBytes != null;
                      if (uploading) {
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: theme.colorScheme.primary),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(15),
                            child: Stack(
                              fit: StackFit.expand,
                              children: <Widget>[
                                Image.memory(
                                  _uploadingPreviewBytes!,
                                  fit: BoxFit.cover,
                                ),
                                Align(
                                  alignment: Alignment.bottomCenter,
                                  child: FractionallySizedBox(
                                    heightFactor:
                                        _uploadingProgress.clamp(0.0, 1.0),
                                    widthFactor: 1.0,
                                    child: Container(
                                      color: theme.colorScheme.primary
                                          .withValues(alpha: 0.6),
                                    ),
                                  ),
                                ),
                                Center(
                                  child: Text(
                                    '${(_uploadingProgress * 100).round()}%',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }
                      return SizedBox(
                        width: 72,
                        height: 72,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: _pickAndUploadAvatar,
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              border:
                                  Border.all(color: theme.colorScheme.outline),
                            ),
                            child: Icon(
                              Icons.add_a_photo,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      );
                    }
                    if (index == 1) {
                      // 「无」占位：默认选中（未选任何头像时）。
                      final bool selectedNone =
                          _avatar == null || _avatar!.isEmpty;
                      return AvatarTile(
                        size: 72,
                        selected: selectedNone,
                        onTap: () => setState(() => _avatar = null),
                        child: Container(
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          alignment: Alignment.center,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: <Widget>[
                              Icon(
                                Icons.person_off_outlined,
                                size: 22,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '无',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    final int uploadIdx = index - 2;
                    if (uploadIdx < _uploadedAvatars.length) {
                      final AvatarItem item = _uploadedAvatars[uploadIdx];
                      final bool selected = _isSelectedUploaded(item.url);
                      return AvatarTile(
                        size: 72,
                        selected: selected,
                        onTap: () => setState(() {
                          _avatar = selected ? null : item.url;
                        }),
                        deleteAction: () => _confirmDeleteAvatar(item),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Image.network(
                            item.url,
                            width: 72,
                            height: 72,
                            fit: BoxFit.cover,
                            errorBuilder: (BuildContext context, Object error,
                                    StackTrace? stack) =>
                                Container(
                              color: theme.colorScheme.surfaceContainerHighest,
                              alignment: Alignment.center,
                              child: Icon(
                                Icons.broken_image_outlined,
                                color: theme.colorScheme.onSurfaceVariant,
                                size: 28,
                              ),
                            ),
                          ),
                        ),
                      );
                    }
                    final int presetIdx = uploadIdx - _uploadedAvatars.length;
                    final String key = _presetAvatars[presetIdx];
                    final bool selected = _isSelectedPreset(key);
                    return AvatarTile(
                      size: 72,
                      selected: selected,
                      onTap: () => setState(() {
                        _avatar = selected ? null : 'preset:$key';
                      }),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.asset(
                          'packages/pscreen_screen/assets/parental/avatars/$key.png',
                          width: 72,
                          height: 72,
                          fit: BoxFit.cover,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: '姓名',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                validator: (String? v) =>
                    (v == null || v.trim().isEmpty) ? '请填写姓名' : null,
              ),
              if (_idError != null) ...<Widget>[
                const SizedBox(height: 6),
                Text(_idError!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.error)),
              ],
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextFormField(
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
                    child: DropdownButtonFormField<String>(
                      initialValue: _profileMode,
                      decoration: const InputDecoration(
                        labelText: '档位',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: const <DropdownMenuItem<String>>[
                        DropdownMenuItem(value: 'mild', child: Text('温和档')),
                        DropdownMenuItem(value: 'strict', child: Text('严格档')),
                      ],
                      onChanged: (String? v) =>
                          setState(() => _profileMode = v ?? 'mild'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextFormField(
                      controller: _daily,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '每日限额(分)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _session,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '单次限额(分)',
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
                    child: TextFormField(
                      controller: _bedStart,
                      decoration: const InputDecoration(
                        labelText: '禁看起(如 22:00)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _bedEnd,
                      decoration: const InputDecoration(
                        labelText: '禁看止(如 06:00)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _blacklist,
                decoration: const InputDecoration(
                  labelText: '黑名单(温和档) · 逗号分隔',
                  hintText: '如：游戏，短视频',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('选人页加密锁'),
                subtitle: const Text('开启后进入该儿童需验证'),
                value: _locked,
                onChanged: (bool v) => setState(() => _locked = v),
              ),
              const SizedBox(height: 8),
              Text(
                '规则（限额 / 时段 / 档位）对分配到本档案的所有电视一致生效，'
                '不按电视单独改（解锁方式仍按电视各自设置）。',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 把档案分配到哪些电视：逐台勾选，保存时按各自当前分配做增删后回写。
class _AssignmentSheet extends StatefulWidget {
  const _AssignmentSheet({
    required this.api,
    required this.child,
    required this.tvs,
  });

  final ParentalAdminApi api;
  final FamilyChild child;
  final List<ParentalMachine> tvs;

  static Future<bool?> show(
    BuildContext context, {
    required ParentalAdminApi api,
    required FamilyChild child,
    required List<ParentalMachine> tvs,
  }) =>
      showModalBottomSheet<bool?>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (BuildContext context) => _AssignmentSheet(
          api: api,
          child: child,
          tvs: tvs,
        ),
      );

  @override
  State<_AssignmentSheet> createState() => _AssignmentSheetState();
}

class _AssignmentSheetState extends State<_AssignmentSheet> {
  /// 每台电视当前已分配的 childIds（用于保存时做差量）。
  final Map<String, List<String>> _current = <String, List<String>>{};

  /// 每台电视分配实体的版本号（D-01：保存时回传 baseRevision）。
  final Map<String, int> _revision = <String, int>{};

  /// 勾选态：本档案是否在该电视启用。
  final Map<String, bool> _checked = <String, bool>{};
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      for (final ParentalMachine tv in widget.tvs) {
        final ParentalAssignment state = await widget.api.fetchAssignmentState(tv.id);
        _current[tv.id] = state.childIds;
        _revision[tv.id] = state.revision;
        _checked[tv.id] = state.childIds.contains(widget.child.id);
      }
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      for (final ParentalMachine tv in widget.tvs) {
        final List<String> base = _current[tv.id] ?? const <String>[];
        final bool want = _checked[tv.id] ?? false;
        final bool has = base.contains(widget.child.id);
        if (want == has) continue;
        final List<String> next = <String>[...base];
        if (want) {
          next.add(widget.child.id);
        } else {
          next.remove(widget.child.id);
        }
        await widget.api.saveAssignment(
          tv.id,
          next,
          baseRevision: _revision[tv.id],
        );
        // 保存成功后该电视版本递增，后续若同一批次再写（不会）也保持一致。
        _revision[tv.id] = (_revision[tv.id] ?? 0) + 1;
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ParentalConflictException catch (e) {
      // D-01：他人已改动该电视的分配 → 提示并回读最新，避免静默覆盖。
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '${e.message}（已为你刷新为最新分配，请重新勾选后再保存）';
      });
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '保存失败：$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '分配「${widget.child.name}」到电视',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: _saving ? null : () => unawaited(_save()),
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('保存'),
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
                      ?.copyWith(color: theme.colorScheme.error)),
            ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (widget.tvs.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('没有可管理的电视，请先在「我的电视」绑定一台电视。'),
            )
          else
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: widget.tvs
                    .map(
                      (ParentalMachine tv) => CheckboxListTile(
                        title: Text(parentalTvName(tv)),
                        subtitle: Text(tv.online ? '在线' : '离线'),
                        value: _checked[tv.id] ?? false,
                        onChanged: (bool? v) =>
                            setState(() => _checked[tv.id] = v ?? false),
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
