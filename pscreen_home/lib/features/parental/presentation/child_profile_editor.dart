import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;
import 'package:pscreen_home/features/parental/data/parental_admin_api.dart';
import 'package:pscreen_home/features/parental/domain/parental_config.dart';
import 'package:pscreen_screen/core/parental/child_avatar.dart';

/// 儿童档案编辑弹窗（方案 4.2 模块①）：新增 / 编辑一份档案。
///
/// 字段按档位显隐（两档语义）：温和档显「隐藏分组 / 隐藏频道」黑名单，
/// 严格档显「白名单分组 / 白名单频道」；限额 / 时段 / `locked` 两档恒显。
/// 保存返回组装好的 [ParentalChild]（编辑时沿用原 id），取消返回 null。
class ChildProfileEditorSheet extends StatefulWidget {
  const ChildProfileEditorSheet({super.key, this.initial, required this.deviceId});

  /// 编辑目标；空 = 新增（保存时生成新 id）。
  final ParentalChild? initial;

  /// 当前编辑的电视设备 id（头像上传/列表都需要）。
  final String deviceId;

  /// 打开编辑弹窗，返回选中的档案（取消为 null）。
  static Future<ParentalChild?> show(
    BuildContext context, {
    ParentalChild? initial,
    required String deviceId,
  }) =>
      showModalBottomSheet<ParentalChild>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (BuildContext context) =>
            ChildProfileEditorSheet(initial: initial, deviceId: deviceId),
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

  /// 当前选中的头像值（`preset:xxx` / `http(s)://...` / null）。
  String? _avatar;

  /// 已上传到 app_server 的素材（从服务端拉取，按家庭维度合并去重）。
  List<AvatarItem> _uploadedAvatars = const <AvatarItem>[];

  /// 预设头像 key → `preset:` 前缀的值。
  final List<String> _presetAvatars = kPresetAvatarKeys;

  /// 上传中状态：null = 空闲；有值 = 上传中（本地预览 bytes，进度由动画驱动）。
  Uint8List? _uploadingPreviewBytes;
  double _uploadingProgress = 0; // 0..1，Timer 驱动

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
    _avatar = initial?.avatar;
    unawaited(_loadUploadedAvatars());
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

  Future<void> _pickAndUploadAvatar() async {
    if (_uploadingPreviewBytes != null) return; // 防重入
    final PlatformFile? file = await FilePicker.pickFile(type: FileType.image);
    if (file == null) return;
    if (!mounted) return;
    try {
      final Uint8List bytes = await file.readAsBytes();
      final img.Image? decoded = img.decodeImage(bytes);
      if (decoded == null) throw Exception('图片格式无法识别');
      final int side = decoded.width < decoded.height ? decoded.width : decoded.height;
      final int offX = (decoded.width - side) ~/ 2;
      final int offY = (decoded.height - side) ~/ 2;
      final img.Image cropped = img.copyCrop(decoded, x: offX, y: offY, width: side, height: side);
      final img.Image resized = img.copyResize(cropped, width: 256, height: 256);
      final Uint8List encoded = Uint8List.fromList(img.encodePng(resized));
      if (!mounted) return;
      // 置上传中状态（显示本地预览 + 半透明进度条上涨）。
      setState(() {
        _uploadingPreviewBytes = encoded;
        _uploadingProgress = 0;
      });
      // 真实进度回调：total 可能为 -1（HTTP 头没给 content-length），
      // 这种回落模式就只显示 bytes/sec 不够直观，所以拿不到 total 时用
      // 本地算出来的 base64 JSON 大小做 total（足够精确，服务端 body 和我们算的一样）。
      final int estimatedTotal = base64Encode(encoded).length + 200; // JSON 包装开销
      final String url = await const ParentalAdminApi().uploadAvatar(
        widget.deviceId,
        bytes: encoded,
        onSendProgress: (int sent, int total) {
          if (!mounted) return;
          final int denom = (total > 0 ? total : estimatedTotal);
          final double p = (sent / denom).clamp(0.0, 1.0);
          if ((p - _uploadingProgress).abs() < 0.025) return; // 节流（Dio 回调很密）
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('头像上传失败：$error')),
        );
      }
    }
  }

  /// 当前选中的头像是否匹配这个上传素材（按 url 比）。
  bool _isSelectedUploaded(String url) => _avatar == url;

  /// 当前选中的头像是否匹配这个预设 key。
  bool _isSelectedPreset(String key) => _avatar == 'preset:$key';

  /// 二次确认删除上传素材。
  /// 注意：服务端只删索引，不删 app_server 物理文件（同一 sha256 可能被其他
  /// 家庭/档案引用）。但这个素材在当前家长的可用列表里会消失，且不再作为
  /// 选项出现；如果某个现有档案的 avatar 恰好指到这张，档案保存时会保留
  /// URL（但用户看不到预览），这是预期行为——档案编辑页重新选一下就好。
  Future<void> _confirmDeleteAvatar(AvatarItem item) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('删除头像？'),
        content: const Text(
          '删除后这个素材在所有设备上都不再显示，但已使用它的档案仍然引用着它。档案里的头像需要重新选择一次才会换掉。',
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败：$error')),
        );
      }
    }
  }

  /// 当前是否有任何头像选中（含预设和上传）。
  bool get _hasAvatarSelected {
    final String? a = _avatar;
    return a != null && a.isNotEmpty;
  }

  /// 从当前表单组装 [ParentalChild]；保存与「是否有未保存改动」判断共用。
  ParentalChild _buildChild() {
    final ParentalChild? initial = widget.initial;
    return ParentalChild(
      id: initial?.id ?? 'c${DateTime.now().millisecondsSinceEpoch}',
      name: _name.text.trim(),
      age: int.tryParse(_age.text.trim()),
      profileMode: _profileMode,
      avatar: _avatar,
      hideGroups: _split(_hideGroups.text),
      hideChannels: _split(_hideChannels.text),
      allowGroups: _split(_allowGroups.text),
      allowChannels: _split(_allowChannels.text),
      sessionLimitMin: _limit(_session.text),
      dailyLimitMin: _limit(_daily.text),
      quietHours: _split(_quietHours.text),
      locked: _locked,
    );
  }

  /// 是否有未保存改动（A7：离开前二次确认）。
  bool _isDirty() {
    final ParentalChild? initial = widget.initial;
    final ParentalChild current = _buildChild();
    if (initial == null) {
      // 新增：仅当真正输入了内容才算脏，避免空表单误弹确认。
      return current.name.isNotEmpty ||
          current.avatar != null ||
          current.profileMode != 'mild' ||
          current.locked ||
          current.age != null ||
          current.hideGroups.isNotEmpty ||
          current.hideChannels.isNotEmpty ||
          current.allowGroups.isNotEmpty ||
          current.allowChannels.isNotEmpty ||
          current.sessionLimitMin != null ||
          current.dailyLimitMin != null ||
          current.quietHours.isNotEmpty;
    }
    return current.name != initial.name ||
        current.age != initial.age ||
        current.profileMode != initial.profileMode ||
        current.avatar != initial.avatar ||
        current.locked != initial.locked ||
        current.hideGroups != initial.hideGroups ||
        current.hideChannels != initial.hideChannels ||
        current.allowGroups != initial.allowGroups ||
        current.allowChannels != initial.allowChannels ||
        current.sessionLimitMin != initial.sessionLimitMin ||
        current.dailyLimitMin != initial.dailyLimitMin ||
        current.quietHours != initial.quietHours;
  }

  /// 未保存改动离开前的二次确认。
  Future<void> _confirmDiscard() async {
    final bool? discard = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('放弃未保存的改动？'),
        content: const Text('你修改了这份儿童档案但还没有保存，离开后改动会丢失。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('继续编辑'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('放弃并返回'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) {
      Navigator.of(context).pop();
    }
  }

  void _save() {
    if (_name.text.trim().isEmpty) {
      setState(() => _nameError = '请填写名称');
      return;
    }
    Navigator.of(context).pop(_buildChild());
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
    return PopScope(
      canPop: !_isDirty(),
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (didPop) return;
        _confirmDiscard();
      },
      child: Padding(
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
              Text('头像', style: theme.textTheme.bodySmall),
              const SizedBox(height: 6),
              SizedBox(
                height: 72,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: 1 + _uploadedAvatars.length + _presetAvatars.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (BuildContext context, int index) {
                    if (index == 0) {
                      final bool uploading = _uploadingPreviewBytes != null;
                      if (uploading) {
                        // 上传中：本地预览 + 半透明蓝色从底部涨到顶部 + 百分比。
                        final ThemeData theme = Theme.of(context);
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
                                // 半透明蓝色层从底部涨到顶部。
                                Align(
                                  alignment: Alignment.bottomCenter,
                                  child: FractionallySizedBox(
                                    heightFactor:
                                        _uploadingProgress.clamp(0.0, 1.0),
                                    widthFactor: 1.0,
                                    child: Container(
                                      color: Colors.blue.withValues(alpha: 0.6),
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
                      // 空闲态上传按钮
                      final ThemeData theme = Theme.of(context);
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
                    int uploadIdx = index - 1;
                    if (uploadIdx < _uploadedAvatars.length) {
                      final AvatarItem item = _uploadedAvatars[uploadIdx];
                      final bool selected = _isSelectedUploaded(item.url);
                      return AvatarTile(
                        size: 72,
                        selected: selected,
                        onTap: () => setState(() {
                          _avatar = selected ? null : item.url;
                        }),
                        // 已上传素材才可以删除（预设是应用内置资源，删不掉）。
                        deleteAction: () => _confirmDeleteAvatar(item),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Image.network(
                            item.url,
                            width: 72,
                            height: 72,
                            fit: BoxFit.cover,
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
              SizedBox(height: _hasAvatarSelected ? 4 : 8),
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
    ),
    );
  }
}

// `_AvatarTile` 已抽取为公共组件 `AvatarTile`，见
// `packages/pscreen_screen/lib/core/parental/child_avatar.dart`。
