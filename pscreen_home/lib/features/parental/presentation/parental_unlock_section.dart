import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pscreen_home/features/parental/data/parental_admin_api.dart';
import 'package:pscreen_home/features/parental/domain/parental_config.dart';
import 'package:pscreen_home/features/parental/presentation/parental_common.dart';

/// 设计稿「我的 → 解锁方式」区块：4 张说明卡 + 顶部「当前配置目标」标注。
///
/// 与 docs/parent-app-redesign-prototype.html 的 .opt 样式对齐：
/// - 每张卡 = 标题 + 说明，选中态浅绿底绿描边 + 「当前」标签；
/// - 点选即生效（保存/回读由 [onSave] 回到页面壳，复用其回读校验与提示）；
/// - PIN 选中时就地展开输入 + 就地「保存 PIN」（不跨 Tab）；
/// - 答题解锁选中时就地给题库入口（不跨 Tab）；
/// - 顶部明确写出解锁方式作用于哪台电视，省去上翻「我的电视」找目标。
///
/// 拆成独立 widget，避免把「我的」页堆成几千行；模式选中态与 PIN 输入由本
/// 组件本地持有，持久化全部回调给页面壳。
class ParentalUnlockSection extends StatefulWidget {
  const ParentalUnlockSection({
    super.key,
    required this.config,
    required this.machine,
    required this.onSave,
    required this.onOpenQuiz,
    this.readOnly = false,
  });

  final ParentalConfig config;

  /// 当前配置目标电视；为空时卡片禁用并提示先去「我的电视」点选一台。
  final ParentalMachine? machine;

  /// 保存整份配置（乐观更新 + 服务端回读）。页面壳的 `_saveConfig`。
  final Future<void> Function(ParentalConfig next) onSave;

  /// 就地打开当前目标电视的答题题库编辑器。
  final VoidCallback onOpenQuiz;

  /// 只读代管（admin）：仅查看，禁用一切写操作（D-03 客户端口径）。
  final bool readOnly;

  @override
  State<ParentalUnlockSection> createState() => _ParentalUnlockSectionState();
}

class _Mode {
  const _Mode(this.key, this.title, this.desc);

  final String key;
  final String title;
  final String desc;
}

class _ParentalUnlockSectionState extends State<ParentalUnlockSection> {
  late String _mode;
  late final TextEditingController _pin;
  String? _pinError;
  bool _saving = false;

  // 文案与设计稿 MODES 一致（短标题，说明原样）。
  static const List<_Mode> _modes = <_Mode>[
    _Mode('remote', '远程确认', '孩子在电视上发起请求，你在手机上批准。推荐，无需额外配置。'),
    _Mode('pin', 'PIN 码', '孩子在电视上输入你设定的数字密码。'),
    _Mode('arith', '算术题', '孩子在电视上做一道随机算术题，答对即解锁。'),
    _Mode('quiz', '答题解锁', '孩子回答你维护的题目，适合把复习内容变成看片门票。'),
  ];

  static const Set<String> _knownModes = <String>{'remote', 'pin', 'arith', 'quiz'};

  // 设计稿配色（parent flavor 固定浅色）。
  static const Color _green = Color(0xFF0F6E56);
  static const Color _selectedBg = Color(0xFFEEF7F3);
  static const Color _chipBg = Color(0xFFE1F5EE);
  static const Color _border = Color(0xFFDDE6E1);
  static const Color _muted = Color(0xFF7B8A85);
  static const Color _targetBorder = Color(0xFFCFE9DF);
  static const Color _warnBg = Color(0xFFFFF8E8);
  static const Color _warnBorder = Color(0xFFF0DCAC);
  static const Color _warnText = Color(0xFF854F0B);

  @override
  void initState() {
    super.initState();
    _mode = _knownModes.contains(widget.config.unlockMode)
        ? widget.config.unlockMode
        : 'remote';
    _pin = TextEditingController(text: widget.config.pin);
  }

  @override
  void didUpdateWidget(covariant ParentalUnlockSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 父级一般用 ValueKey 重建；这里兜底同步服务端回读后的值，避免切设备后回显旧态。
    if (oldWidget.config.unlockMode != widget.config.unlockMode) {
      _mode = _knownModes.contains(widget.config.unlockMode)
          ? widget.config.unlockMode
          : 'remote';
    }
    if (oldWidget.config.pin != widget.config.pin && _pin.text != widget.config.pin) {
      _pin.text = widget.config.pin;
    }
  }

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _selectMode(String key) async {
    if (_saving || key == _mode || widget.machine == null) return;
    setState(() {
      _mode = key;
      _pinError = null;
      _saving = true;
    });
    try {
      await widget.onSave(widget.config.copyWith(
        unlockMode: key,
        // 切到 PIN 时用现输入框值；其它模式沿用原 PIN，不误清空。
        pin: key == 'pin' ? _pin.text.trim() : widget.config.pin,
      ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _savePin() async {
    final String pin = _pin.text.trim();
    if (pin.length != 4 || int.tryParse(pin) == null) {
      setState(() => _pinError = 'PIN 需为 4 位数字');
      return;
    }
    setState(() {
      _pinError = null;
      _saving = true;
    });
    try {
      await widget.onSave(widget.config.copyWith(unlockMode: 'pin', pin: pin));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ParentalMachine? machine = widget.machine;
    final String targetName = machine == null ? '' : parentalTvName(machine);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(
              '解锁方式',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            if (widget.readOnly) _chip(text: '只读代管', bg: _chipBg, fg: _green),
            if (machine != null) _chip(text: targetName, bg: _chipBg, fg: _green),
          ],
        ),
        const SizedBox(height: 6),
        machine == null ? _noTargetCard() : _targetCard(targetName),
        const SizedBox(height: 8),
        for (final _Mode m in _modes)
          _modeCard(theme, m, machine != null && !widget.readOnly),
        if (widget.readOnly)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F3),
                border: Border.all(color: _border),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                '只读代管：解锁方式仅供查看，修改需由绑定该电视的家长操作。',
                style: TextStyle(fontSize: 11, color: _muted, height: 1.4),
              ),
            ),
          ),
        _footnote(),
      ],
    );
  }

  Widget _chip({required String text, required Color bg, required Color fg}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }

  Widget _targetCard(String targetName) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: _selectedBg,
        border: Border.all(color: _targetBorder),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '当前配置目标：$targetName · 下面四种方式只对这台电视生效。'
        '要改别的电视，去上面「我的电视」点它的名字切换。',
        style: const TextStyle(fontSize: 11, color: _green, height: 1.4),
      ),
    );
  }

  Widget _noTargetCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F3),
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Text(
        '未选择电视 · 请先在上方「我的电视」点一台，把它设为「当前配置目标」后，解锁方式才能生效。',
        style: TextStyle(fontSize: 11, color: _muted, height: 1.4),
      ),
    );
  }

  Widget _modeCard(ThemeData theme, _Mode m, bool enabled) {
    final bool on = _mode == m.key;
    final BorderRadius radius = BorderRadius.circular(9);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      margin: const EdgeInsets.only(bottom: 7),
      decoration: BoxDecoration(
        color: on ? _selectedBg : Colors.white,
        border: Border.all(color: on ? _green : _border),
        borderRadius: radius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // 只有标题+说明这一块可点选切换；下方 PIN/题库扩展区独立，点击不冒泡。
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(9)),
              onTap: enabled && !_saving ? () => unawaited(_selectMode(m.key)) : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Text(
                          m.title,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        const Spacer(),
                        if (on) _chip(text: '当前', bg: _chipBg, fg: _green),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      m.desc,
                      style: const TextStyle(fontSize: 11, color: _muted, height: 1.35),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (on && m.key == 'pin')
            Padding(
              padding: const EdgeInsets.fromLTRB(11, 0, 11, 10),
              child: _pinEditor(theme),
            ),
          if (on && m.key == 'quiz')
            Padding(
              padding: const EdgeInsets.fromLTRB(11, 0, 11, 10),
              child: _quizHint(),
            ),
        ],
      ),
    );
  }

  Widget _pinEditor(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        TextField(
          controller: _pin,
          keyboardType: TextInputType.number,
          maxLength: 4,
          enabled: !_saving && !widget.readOnly,
          onEditingComplete: () => unawaited(_savePin()),
          decoration: const InputDecoration(
            labelText: '设定 PIN（4 位数字）',
            border: OutlineInputBorder(),
            isDense: true,
            counterText: '',
          ),
        ),
        if (_pinError != null)
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text(
              _pinError!,
              style: TextStyle(fontSize: 11, color: theme.colorScheme.error),
            ),
          ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _saving ? null : () => unawaited(_savePin()),
            child: const Text('保存 PIN'),
          ),
        ),
      ],
    );
  }

  Widget _quizHint() {
    return Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: _warnBg,
        border: Border.all(color: _warnBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: <Widget>[
          const Expanded(
            child: Text(
              '答题解锁需要题库；题库为空或只有填空题时，电视会回退短码页。',
              style: TextStyle(fontSize: 11, color: _warnText, height: 1.35),
            ),
          ),
          const SizedBox(width: 6),
          TextButton(
            onPressed: (_saving || widget.readOnly) ? null : widget.onOpenQuiz,
            child: const Text('管理题库 ›'),
          ),
        ],
      ),
    );
  }

  Widget _footnote() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Text(
        '选择后立即生效并回读确认；若前置条件没满足，会在这张卡片里就地给出入口，不用跨 Tab 找。',
        style: TextStyle(fontSize: 11, color: _muted, height: 1.4),
      ),
    );
  }
}
