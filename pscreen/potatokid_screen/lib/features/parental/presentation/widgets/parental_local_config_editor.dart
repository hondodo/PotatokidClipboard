import 'package:flutter/material.dart';
import 'package:pscreen_screen/core/parental/parental_config.dart';
import 'package:pscreen_screen/core/parental/parental_state_controller.dart';

/// 儿童模式本地临时配置编辑器（阶段 1 调试入口的内嵌编辑区）。
///
/// 承载能力（方案 §7 阶段 1 验收）：
/// - 查看/编辑 `mode` 总开关；
/// - 查看/编辑 `children[]`：id / name / 档位（温和/严格）/ 单次与当日限额 /
///   禁看时段，可增删档案；
/// - 勾选「当前观看」设置 `activeChildIds`（模拟换人）；
/// - 保存走 [ParentalStateController.saveLocalConfig]（内存 + 落盘 +
///   `_syncTimer` 即时生效），随后 [ParentalStateController.setActiveChildren]
///   应用换人分账（无变化时控制器内部早返回）。
///
/// 打开方式：「我的」页**长按「版本」行**（隐藏手势，见
/// `profile_page._openParentalDebug`），经既有 settings sheet 路由展示。
class ParentalLocalConfigEditor extends StatefulWidget {
  const ParentalLocalConfigEditor({super.key});

  @override
  State<ParentalLocalConfigEditor> createState() =>
      _ParentalLocalConfigEditorState();
}

class _ParentalLocalConfigEditorState
    extends State<ParentalLocalConfigEditor> {
  late bool _modeOn;
  late List<_ChildDraft> _drafts;

  /// 最近一次保存结果（内联展示；sheet 无 Scaffold，不用 SnackBar）。
  String _result = '';

  @override
  void initState() {
    super.initState();
    final ParentalStateController parental = ParentalStateController.instance;
    _modeOn = parental.config.mode == 'on';
    final Set<String> active = parental.activeChildIds.toSet();
    _drafts = <_ChildDraft>[
      for (final ChildProfile p in parental.config.children)
        _ChildDraft.from(p, active: active.contains(p.id)),
    ];
  }

  @override
  void dispose() {
    for (final _ChildDraft d in _drafts) {
      d.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    final ParentalStateController parental = ParentalStateController.instance;
    final bool effective = _modeOn && _drafts.isNotEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text('本地临时配置', style: textTheme.titleMedium),
            ),
            Text(effective ? '已启用' : '未启用', style: textTheme.bodySmall),
            Switch(
              value: _modeOn,
              onChanged: (bool v) => setState(() => _modeOn = v),
            ),
          ],
        ),
        Text(
          '生效判定：开关为「开」且档案列表非空（保存后立即写入本地并同步计时器）。',
          style: textTheme.bodySmall,
        ),
        if (parental.serverConfigured)
          Text(
            '服务端已配置儿童模式（阶段 3 起为权威源）：本地修改仅即时生效，'
            '下一次 config 推送 / 重启后仍以服务端为准——本区仅作调试入口。',
            style: textTheme.bodySmall?.copyWith(color: Colors.orangeAccent),
          ),
        const SizedBox(height: 4),
        Text(
          '勾选「当前观看」的孩子即 activeChildIds，保存后立即切换分账（模拟换人）。',
          style: textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        for (final _ChildDraft d in _drafts) _buildCard(d),
        OutlinedButton.icon(
          onPressed: _addDraft,
          icon: const Icon(Icons.add),
          label: const Text('添加档案'),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _save,
          child: const Text('保存并生效（saveLocalConfig）'),
        ),
        if (_result.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          Text(_result, style: textTheme.bodySmall),
        ],
      ],
    );
  }

  /// 单个孩子档案的编辑卡片。
  Widget _buildCard(_ChildDraft d) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: d.idCtrl,
                    decoration: const InputDecoration(
                      labelText: '档案 ID（唯一，保存时去重）',
                      isDense: true,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => _removeDraft(d),
                  tooltip: '删除该档案',
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            TextField(
              controller: d.nameCtrl,
              decoration: const InputDecoration(
                labelText: '名称（选人页/锁屏显示）',
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                OutlinedButton(
                  onPressed: () => setState(() => d.strict = !d.strict),
                  child: Text(d.strict ? '严格档（白名单）' : '温和档（黑名单）'),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: d.sessionCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '单次限额（分钟，0=不启用）',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: d.dailyCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '当日限额（分钟，0=不启用）',
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            TextField(
              controller: d.quietCtrl,
              decoration: const InputDecoration(
                labelText: '禁看时段 HH:MM-HH:MM（多个用逗号分隔，可跨午夜）',
                isDense: true,
              ),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('当前观看（activeChildIds）'),
              value: d.active,
              onChanged: (bool? v) => setState(() => d.active = v ?? false),
            ),
          ],
        ),
      ),
    );
  }

  void _addDraft() {
    setState(() {
      _drafts.add(_ChildDraft.empty(_freeId()));
    });
  }

  /// 新档案的兜底 ID：`child1`、`child2`… 避开已有 ID。
  String _freeId() {
    final Set<String> used =
        _drafts.map((_ChildDraft d) => d.idCtrl.text.trim()).toSet();
    int n = _drafts.length + 1;
    while (used.contains('child$n')) {
      n++;
    }
    return 'child$n';
  }

  void _removeDraft(_ChildDraft d) {
    setState(() {
      _drafts.remove(d);
      d.dispose();
    });
  }

  /// 解析草稿 → 构造 [ParentalConfig] → [ParentalStateController.saveLocalConfig]
  /// → [ParentalStateController.setActiveChildren]（换人）。
  Future<void> _save() async {
    final ParentalStateController parental = ParentalStateController.instance;
    final ParentalConfig old = parental.config;
    final List<ChildProfile> children = <ChildProfile>[];
    final List<String> active = <String>[];
    final Set<String> seen = <String>{};
    final List<String> warnings = <String>[];
    for (final _ChildDraft d in _drafts) {
      final String id = d.idCtrl.text.trim();
      if (id.isEmpty) {
        warnings.add('存在空 ID 档案，已跳过');
        continue;
      }
      if (!seen.add(id)) {
        warnings.add('重复 ID「$id」已跳过');
        continue;
      }
      final String name = d.nameCtrl.text.trim();
      // 未在编辑器暴露的字段（年龄/受保护/黑白名单）按原 ID 保留，避免保存时丢失。
      final ChildProfile? prev = old.childById(id);
      final List<QuietHour> quiet = <QuietHour>[];
      int badQuiet = 0;
      for (final String raw
          in d.quietCtrl.text.split(RegExp(r'[,;，；]+'))) {
        if (raw.trim().isEmpty) continue;
        final QuietHour? q = QuietHour.tryParse(raw);
        if (q == null) {
          badQuiet++;
        } else {
          quiet.add(q);
        }
      }
      if (badQuiet > 0) {
        warnings.add('「$id」有 $badQuiet 条禁看时段格式非法，已忽略');
      }
      children.add(
        ChildProfile(
          id: id,
          name: name.isEmpty ? id : name,
          age: prev?.age,
          profileMode: d.strict ? 'strict' : 'mild',
          locked: prev?.locked ?? false,
          avatar: prev?.avatar,
          hideGroups: prev?.hideGroups ?? const <String>[],
          hideChannels: prev?.hideChannels ?? const <String>[],
          allowGroups: prev?.allowGroups ?? const <String>[],
          allowChannels: prev?.allowChannels ?? const <String>[],
          sessionLimitMin: _nonNeg(d.sessionCtrl.text),
          dailyLimitMin: _nonNeg(d.dailyCtrl.text),
          quietHours: quiet,
        ),
      );
      if (d.active) active.add(id);
    }
    final ParentalConfig next = ParentalConfig(
      mode: _modeOn ? 'on' : 'off',
      activeChildIds: active,
      children: children,
      unlockMode: old.unlockMode,
      pin: old.pin,
      ownerAccount: old.ownerAccount,
    );
    await parental.saveLocalConfig(next);
    await parental.setActiveChildren(active);
    if (!mounted) return;
    setState(() {
      _result = '已保存：${children.length} 个档案，观看者 '
          '${active.isEmpty ? '（无）' : active.join('、')}'
          '${warnings.isEmpty ? '' : '；${warnings.join('；')}'}';
    });
  }

  /// 非负整数解析（空串/非法/负数 → 0，与 `ChildProfile` 的 0=不启用口径一致）。
  static int _nonNeg(String raw) {
    final int? v = int.tryParse(raw.trim());
    if (v == null || v < 0) return 0;
    return v;
  }
}

/// 一个孩子档案的编辑草稿（持有五个输入框的生命周期）。
class _ChildDraft {
  _ChildDraft._({
    required this.idCtrl,
    required this.nameCtrl,
    required this.sessionCtrl,
    required this.dailyCtrl,
    required this.quietCtrl,
    required this.strict,
    required this.active,
  });

  factory _ChildDraft.from(ChildProfile p, {required bool active}) =>
      _ChildDraft._(
        idCtrl: TextEditingController(text: p.id),
        nameCtrl: TextEditingController(text: p.name),
        sessionCtrl: TextEditingController(text: '${p.sessionLimitMin}'),
        dailyCtrl: TextEditingController(text: '${p.dailyLimitMin}'),
        quietCtrl: TextEditingController(
          text: p.quietHours.map((QuietHour q) => q.format()).join(', '),
        ),
        strict: p.isStrict,
        active: active,
      );

  /// 新档案的默认草稿（默认限额便于立刻验证计时链路，0=不启用）。
  factory _ChildDraft.empty(String id) => _ChildDraft._(
        idCtrl: TextEditingController(text: id),
        nameCtrl: TextEditingController(),
        sessionCtrl: TextEditingController(text: '30'),
        dailyCtrl: TextEditingController(text: '120'),
        quietCtrl: TextEditingController(),
        strict: false,
        active: false,
      );

  final TextEditingController idCtrl;
  final TextEditingController nameCtrl;
  final TextEditingController sessionCtrl;
  final TextEditingController dailyCtrl;
  final TextEditingController quietCtrl;
  bool strict;
  bool active;

  void dispose() {
    idCtrl.dispose();
    nameCtrl.dispose();
    sessionCtrl.dispose();
    dailyCtrl.dispose();
    quietCtrl.dispose();
  }
}
