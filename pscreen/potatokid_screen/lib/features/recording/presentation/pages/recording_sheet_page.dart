import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:potatokid_screen/app/app_flavor.dart';

import 'package:pscreen_screen/features/iptv/application/recording/recording_library_controller.dart';
import 'package:pscreen_screen/features/iptv/application/recording/recording_platform.dart'
    show RecordedFile;
import 'package:pscreen_screen/features/iptv/application/recording/recording_storage.dart';
import 'package:potatokid_screen/core/di/injection.dart';
import 'package:potatokid_screen/core/router/app_router.dart';
import 'package:potatokid_screen/core/router/route_params.dart';
import 'package:potatokid_screen/shared/widgets/kid_chrome.dart';

/// 录制中心页（TV 风格）。
///
/// 视觉对齐「我的 → 设置」页：全屏、单列分组、大字号左右行、焦点高亮行、
/// 胶囊按钮；取消 Material 底部 sheet 与 TabBar 的割裂长相。
///
/// 双配色跟随全项目唯一判定式 [kidModeOn]：
/// - 儿童：KidPalette 深蓝渐变 + 暖黄强调 + 白描边焦点；
/// - 普通：成人深蓝面板 + 品牌蓝 / 橙选中，蓝色焦点框。
///
/// 本页只维护「焦点落在第几行 + 每行的激活/步进回调」，不自己接遥控按键；
/// 遥控由 MainApp 的统一分发入口按当前页状态集中转发（见集中 if 分支）。
class RecordingSheetPage extends StatefulWidget {
  const RecordingSheetPage({super.key});

  // ── 遥控桥接（与 ProfilePage.onSubmitInlineEdit 同构）────────────
  // 页面只暴露「原子操作」，不自己判断按键；集中分发在 MainApp._handleOverlayRoute。
  // 打开时注册、关闭时清空；isActive 由 MainApp 与当前路由一起判断。
  static void Function(int delta)? onMoveFocus; // 上下换行：delta -1 上 / +1 下
  static void Function(int delta)? onStepValue; // 左右改值：仅步进行响应
  static VoidCallback? onActivate; // OK：激活当前聚焦行
  static bool get isActive => onMoveFocus != null;

  @override
  State<RecordingSheetPage> createState() => _RecordingSheetPageState();
}

class _RecordingSheetPageState extends State<RecordingSheetPage> {
  final RecordingStorage _storage = RecordingStorage();
  final RecordingLibraryController _library = RecordingLibraryController.instance;

  // 纯索引式视觉焦点：不创建/不抢占任何 FocusNode。
  // 录制页是 push 到根 Navigator 的覆盖路由，若它抢占焦点，按键会在本页焦点树
  // 冒泡、不经过 MainApp 根 Focus，集中遥控分发就断了。焦点必须留在 MainApp，
  // 本页只用一个索引画高亮，方向键由 MainApp 集中转发。
  int _focused = 0;
  int _rowCount = 0;

  /// 行内子焦点：0=左侧按钮，1=右侧按钮。
  /// 存储位置行（选目录/恢复内部）与文件行（播放/删除）共用；
  /// 换到新行时复位为 0，左右键切换，OK 执行当前高亮的按钮。
  int _subFocus = 0;

  /// 每行的稳定 GlobalKey（按焦点行号 0.._rowCount-1），供遥控换行时
  /// Scrollable.ensureVisible 把焦点行滚进可视区。分组标题不占焦点行号。
  final List<GlobalKey> _rowKeys = <GlobalKey>[];

  late String _locationLabel;
  late int _maxMb;
  late int _lowMb;
  String _freeText = '—';

  static const List<int> _maxOptions = <int>[512, 1024, 2048, 4096];
  static const List<int> _lowOptions = <int>[256, 512, 1024, 2048];

  // ---------- 普通（成人）模式配色；儿童模式取 KidPalette ----------
  static const Color _adultBgTop = Color(0xFF111722);
  static const Color _adultBgBottom = Color(0xFF121722);
  static const Color _adultSurface = Color(0xFF263247);
  static const Color _adultSurface2 = Color(0xFF1E2A3C);
  static const Color _adultLine = Color(0xFF3A4A63);
  static const Color _adultText = Color(0xFFEEF1F6);
  static const Color _adultText2 = Color(0xFFA9B4C6);
  static const Color _adultAccent = Color(0xFF8FB4FF);
  static const Color _adultFocus = Color(0xFF8FB4FF);
  static const Color _adultFocusBg = Color(0x2B6496FF);
  static const Color _danger = Color(0xFFFF7A7A);

  bool get _kid => kidModeOn;

  LinearGradient get _pageBg => _kid
      ? KidPalette.background
      : const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[_adultBgTop, _adultBgBottom],
        );
  Color get _surface => _kid ? KidPalette.capsule : _adultSurface;
  Color get _surface2 => _kid ? KidPalette.dialogMid : _adultSurface2;
  Color get _line => _kid ? Colors.white24 : _adultLine;
  Color get _text => _kid ? Colors.white : _adultText;
  Color get _text2 => _kid ? KidPalette.softBlue : _adultText2;
  Color get _accent => _kid ? KidPalette.accent : _adultAccent;
  Color get _focusBorder => _kid ? Colors.white : _adultFocus;
  Color get _focusBg => _kid ? const Color(0x33FFD166) : _adultFocusBg;

  @override
  void initState() {
    super.initState();
    _sync();
    _loadFree();
    _library.refresh();
    // 注册遥控桥接：集中分发入口只需要调用这几个原子操作。
    RecordingSheetPage.onMoveFocus = (int delta) => _moveFocus(delta);
    RecordingSheetPage.onStepValue = _stepFocused;
    RecordingSheetPage.onActivate = activateFocused;
  }

  @override
  void dispose() {
    RecordingSheetPage.onMoveFocus = null;
    RecordingSheetPage.onStepValue = null;
    RecordingSheetPage.onActivate = null;
    super.dispose();
  }

  void _sync() {
    _locationLabel = _storage.locationLabel;
    _maxMb = (_storage.maxFileBytes / (1024 * 1024)).round();
    _lowMb = (_storage.lowSpaceBytes / (1024 * 1024)).round();
  }

  Future<void> _loadFree() async {
    final int free = await _storage.freeBytes();
    if (!mounted) return;
    setState(() {
      _freeText = free < 0
          ? 'recording_space_unknown'.tr()
          : RecordingLibraryController.formatSize(free);
    });
  }

  Future<void> _pickDir() async {
    final bool ok = await _storage.pickAndSetDirectory();
    if (!mounted) return;
    if (ok) {
      setState(_sync);
      await _loadFree();
      await _library.refresh();
    }
  }

  Future<void> _useInternal() async {
    await _storage.useInternal();
    if (!mounted) return;
    setState(_sync);
    await _loadFree();
    await _library.refresh();
  }

  Future<void> _stepMax(int delta) async {
    int idx = _maxOptions.indexOf(_maxMb);
    if (idx < 0) idx = 2;
    final int next = (idx + delta).clamp(0, _maxOptions.length - 1);
    await _storage.setMaxFileMb(_maxOptions[next]);
    if (!mounted) return;
    setState(() => _maxMb = _maxOptions[next]);
  }

  Future<void> _stepLow(int delta) async {
    int idx = _lowOptions.indexOf(_lowMb);
    if (idx < 0) idx = 1;
    final int next = (idx + delta).clamp(0, _lowOptions.length - 1);
    await _storage.setLowSpaceMb(_lowOptions[next]);
    if (!mounted) return;
    setState(() => _lowMb = _lowOptions[next]);
  }

  Future<void> _play(RecordedFile file) async {
    await Injection.get<AppRouter>().pushRecordingPlayback(
          RecordingPlaybackParams(uri: file.uri, title: file.name),
        );
  }

  Future<void> _delete(RecordedFile file) async {
    final bool ok = await _library.delete(file);
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(
          ok ? 'recording_deleted'.tr() : 'recording_delete_failed'.tr(),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// 纯索引移动：只改高亮索引，不碰任何 FocusNode（见 _focused 说明）。
  /// 移动后把焦点行滚进可视区——否则焦点落在屏幕外时遥控看不到选中内容。
  void _moveFocus(int delta) {
    if (_rowCount <= 0) return;
    final int next =
        math.min(math.max(_focused + delta, 0), _rowCount - 1);
    if (next == _focused) return;
    setState(() {
      _focused = next;
      // 换到新行：子焦点复位到左侧按钮。左右切子焦点不走这里。
      _subFocus = 0;
    });
    // 等本帧把高亮画出来后再滚动，确保拿到的是最新布局。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || next >= _rowKeys.length) return;
      final BuildContext? ctx = _rowKeys[next].currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.5,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// 触屏点选某行：同步高亮索引（触屏仍可用，且高亮与遥控保持一致）。
  void _tapRow(int index) => _moveFocus(index - _focused);

  /// 左右键：在当前行的两个按钮间切换子焦点（通用）。
  void _stepSubFocus(int delta) {
    final int next = (_subFocus + delta).clamp(0, 1);
    if (next == _subFocus) return;
    setState(() => _subFocus = next);
  }

  /// 供 MainApp 集中遥控入口调用：左右改值（仅步进行响应）。
  void _stepFocused(int delta) {
    final List<VoidCallback?> table = delta < 0 ? _leftActions : _rightActions;
    final int i = math.min(_focused, table.length - 1);
    if (i < 0) return;
    table[i]?.call();
  }

  /// 供 MainApp 集中遥控入口调用：当前行激活（OK）。
  void activateFocused() {
    final int i = math.min(_focused, _actions.length - 1);
    if (i < 0) return;
    _actions[i]?.call();
  }

  /// 焦点行 -> 动作表，build 时重建，供集中遥控 OK / 左右键直接命中。
  final List<VoidCallback?> _actions = <VoidCallback?>[];
  final List<VoidCallback?> _leftActions = <VoidCallback?>[];
  final List<VoidCallback?> _rightActions = <VoidCallback?>[];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<RecordedFile>>(
      valueListenable: _library.items,
      builder: (context, files, _) {
        // 4 个设置行 + N 个文件行（空列表时放 1 个占位行）
        final int count = 4 + (files.isEmpty ? 1 : files.length);
        _rowCount = count;
        if (_focused >= count) _focused = count - 1;
        // 行数变化时增补/裁剪 key（分组标题不占焦点行号，从 0 顺序编号）。
        while (_rowKeys.length < count) {
          _rowKeys.add(GlobalKey());
        }
        while (_rowKeys.length > count) {
          _rowKeys.removeLast();
        }

        final List<Widget> rows = <Widget>[];
        // 三张动作表与行号一一对应：OK / 左 / 右。集中遥控入口按下时直取。
        // 存储位置行两个按钮（内部/改路径）与文件行共用子焦点 _subFocus：
        // 左右切按钮高亮，OK 执行当前高亮的按钮。
        _actions
          ..clear()
          ..addAll(<VoidCallback?>[
            () => _subFocus == 0 ? _useInternal() : _pickDir(), // 0 存储位置
            _loadFree, // 1 可用空间：OK 刷新
            null, // 2 单文件上限：左右改值，OK 空
            null, // 3 低空间阈值：左右改值，OK 空
          ]);
        _leftActions
          ..clear()
          ..addAll(<VoidCallback?>[
            () => _stepSubFocus(-1), // 0 存储位置：左切按钮
            null,
            () => _stepMax(-1),
            () => _stepLow(-1),
          ]);
        _rightActions
          ..clear()
          ..addAll(<VoidCallback?>[
            () => _stepSubFocus(1), // 0 存储位置：右切按钮
            null,
            () => _stepMax(1),
            () => _stepLow(1),
          ]);

        // —— 分组 1：录制设置 ——
        rows.add(_groupTitle('recording_tab_settings'.tr()));
        rows.add(_row(
          index: 0,
          rowKey: _rowKeys[0],
          label: 'recording_location'.tr(),
          sub: _locationLabel,
          right: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _pill('recording_btn_internal'.tr(), _useInternal,
                  highlight: _focused == 0 && _subFocus == 0),
              const SizedBox(width: 10),
              _pill('recording_btn_change_path'.tr(), _pickDir,
                  highlight: _focused == 0 && _subFocus == 1),
            ],
          ),
        ));
        rows.add(_row(
          index: 1,
          rowKey: _rowKeys[1],
          label: 'recording_free_space'.tr(),
          right: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                _freeText,
                style: TextStyle(color: _text2, fontSize: 18),
              ),
              const SizedBox(width: 10),
              _iconAction(Icons.refresh, _loadFree,
                  highlight: _focused == 1),
            ],
          ),
        ));
        rows.add(_row(
          index: 2,
          rowKey: _rowKeys[2],
          label: 'recording_max_file'.tr(),
          value: '$_maxMb MB',
          steppable: true,
          onLeft: () => _stepMax(-1),
          onRight: () => _stepMax(1),
        ));
        rows.add(_row(
          index: 3,
          rowKey: _rowKeys[3],
          label: 'recording_low_space'.tr(),
          value: '$_lowMb MB',
          steppable: true,
          onLeft: () => _stepLow(-1),
          onRight: () => _stepLow(1),
        ));

        // —— 分组 2：录制文件 ——
        rows.add(_groupTitle(
          '${'recording_tab_files'.tr()} · ${files.length}',
        ));
        if (files.isEmpty) {
          rows.add(_row(
            index: 4,
            rowKey: _rowKeys[4],
            label: 'recording_empty'.tr(),
            muted: true,
          ));
          _actions.add(null);
          _leftActions.add(null);
          _rightActions.add(null);
        } else {
          for (int i = 0; i < files.length; i++) {
            final RecordedFile f = files[i];
            final int idx = 4 + i;
            rows.add(_fileRow(
              index: idx,
              rowKey: _rowKeys[idx],
              file: f,
              buttonIndex: _focused == idx ? _subFocus : -1,
              onPlay: () => _play(f),
              onDelete: () => _delete(f),
            ));
            // 文件行：左右切「播放/删除」子焦点，OK 执行当前高亮的按钮。
            _actions.add(() =>
                _subFocus == 0 ? _play(f) : _delete(f));
            _leftActions.add(() => _stepSubFocus(-1));
            _rightActions.add(() => _stepSubFocus(1));
          }
        }

        return Scaffold(
          body: Container(
            decoration: BoxDecoration(gradient: _pageBg),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 56,
                  vertical: 36,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _topBar(),
                    const SizedBox(height: 10),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: rows,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        children: <Widget>[
          _backButton(),
          const SizedBox(width: 18),
          Text(
            'recording_center_title'.tr(),
            style: TextStyle(
              color: _text,
              fontSize: 34,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// 触屏返回：仅 phone / board 显示（有触屏的变体）；tv 只有遥控，
  /// 返回由实体返回键承担（见 MainApp 集中遥控分发），不显示可点按钮避免
  /// 与焦点树打架。本页是 push 出来的覆盖路由，点击直接 pop 自己，
  /// 不走 TouchBackController 的底层分层返回（那条链在 cur==0 会误操作频道）。
  Widget _backButton() {
    if (AppFlavorConfig.flavor == AppFlavor.tv) {
      return const SizedBox.shrink();
    }
    return Semantics(
      button: true,
      child: GestureDetector(
        onTap: () => Injection.get<AppRouter>().pop(),
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: _surface2,
            shape: BoxShape.circle,
            border: Border.all(color: _line),
          ),
          child: Icon(Icons.arrow_back_rounded, color: _text, size: 26),
        ),
      ),
    );
  }

  Widget _groupTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 10, left: 4),
      child: Row(
        children: <Widget>[
          Container(
            width: 5,
            height: 18,
            decoration: BoxDecoration(
              color: _accent,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            text,
            style: TextStyle(color: _accent, fontSize: 19),
          ),
        ],
      ),
    );
  }

  Widget _row({
    required int index,
    required GlobalKey rowKey,
    required String label,
    String? sub,
    String? value,
    Widget? right,
    bool muted = false,
    bool steppable = false,
    VoidCallback? onLeft,
    VoidCallback? onRight,
  }) {
    final bool focused = _focused == index;
    final Widget rightWidget = right ??
        (steppable
            ? _stepper(value: value ?? '', onLeft: onLeft, onRight: onRight)
            : (value != null
                ? Text(
                    value,
                    style: TextStyle(
                      color: muted ? _text2 : _accent,
                      fontSize: muted ? 19 : 24,
                      fontWeight: muted ? FontWeight.w400 : FontWeight.w600,
                    ),
                  )
                : const SizedBox.shrink()));

    return GestureDetector(
        key: rowKey,
        onTap: () => _tapRow(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
          decoration: BoxDecoration(
            color: focused ? _focusBg : _surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: focused ? _focusBorder : _line,
              width: focused ? 2.5 : 1,
            ),
            boxShadow: <BoxShadow>[
              if (focused)
                BoxShadow(
                  color: _focusBg,
                  blurRadius: 22,
                ),
            ],
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      label,
                      style: TextStyle(
                        color: _text,
                        fontSize: 24,
                      ),
                    ),
                    if (sub != null && sub.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          sub,
                          style: TextStyle(color: _text2, fontSize: 16),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              rightWidget,
            ],
          ),
        ),
    );
  }

  Widget _fileRow({
    required int index,
    required GlobalKey rowKey,
    required RecordedFile file,
    required int buttonIndex,
    required VoidCallback onPlay,
    required VoidCallback onDelete,
  }) {
    final bool focused = _focused == index;
    return GestureDetector(
        key: rowKey,
        onTap: () => _tapRow(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
          decoration: BoxDecoration(
            color: focused ? _focusBg : _surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: focused ? _focusBorder : _line,
              width: focused ? 2.5 : 1,
            ),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      file.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: _text, fontSize: 22),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      RecordingLibraryController.formatSize(file.size),
                      style: TextStyle(color: _text2, fontSize: 16),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              _pill('recording_play'.tr(), onPlay,
                  highlight: buttonIndex == 0),
              const SizedBox(width: 10),
              _pill('recording_delete'.tr(), onDelete,
                  danger: true, highlight: buttonIndex == 1),
            ],
          ),
        ),
    );
  }

  Widget _pill(String text, VoidCallback onTap,
      {bool danger = false, bool boxed = true, bool highlight = false}) {
    final Widget label = Text(
      text,
      style: TextStyle(
        color: danger ? _danger : _accent,
        fontSize: 18,
        fontWeight: highlight ? FontWeight.w700 : FontWeight.w400,
      ),
    );
    if (!boxed) {
      // 纯文本值：不画胶囊背景/边框，避免被误认为独立按钮。
      // 仍保留点击（触屏点值可选/改目录），但视觉上只是这一行的值。
      return InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: label,
        ),
      );
    }
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
        decoration: BoxDecoration(
          color: highlight ? _focusBg : _surface2,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: highlight ? _focusBorder : _line,
            width: highlight ? 2 : 1,
          ),
          boxShadow: <BoxShadow>[
            if (highlight) BoxShadow(color: _focusBg, blurRadius: 16),
          ],
        ),
        child: label,
      ),
    );
  }

  Widget _iconAction(IconData icon, VoidCallback onTap,
      {bool highlight = false}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: highlight ? _focusBg : _surface2,
          shape: BoxShape.circle,
          border: Border.all(
            color: highlight ? _focusBorder : _line,
            width: highlight ? 2 : 1,
          ),
          boxShadow: <BoxShadow>[
            if (highlight) BoxShadow(color: _focusBg, blurRadius: 16),
          ],
        ),
        child: Icon(icon, color: highlight ? _focusBorder : _text, size: 22),
      ),
    );
  }

  Widget _stepper({
    required String value,
    VoidCallback? onLeft,
    VoidCallback? onRight,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _stepIcon(Icons.chevron_left, onLeft, active: onLeft != null),
        const SizedBox(width: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 90),
          child: Text(
            value,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _accent,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 8),
        _stepIcon(Icons.chevron_right, onRight, active: onRight != null),
      ],
    );
  }

  Widget _stepIcon(IconData icon, VoidCallback? onTap, {bool active = true}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Icon(
        icon,
        color: active ? _accent : _line,
        size: 26,
      ),
    );
  }
}
