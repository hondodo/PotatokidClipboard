import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pscreen_screen/core/parental/parental_state_controller.dart';
import 'package:pscreen_screen/core/update/app_update_controller.dart';

/// 电视端右上角的蓝色「更新」胶囊（圆角 + 下载图标 + 百分比）。
///
/// 电视端没有 AppBar，这里作为首页播放器上的悬浮层；下载中只展示进度，
/// 不拦截播放/操作。下载校验完成后点按才拉起系统安装器。
///
/// 遥控焦点保障：胶囊是右上角的孤立可聚焦物（方向键按 ↑/→ 按 Flutter
/// 默认几何遍历必达），获得焦点时**放大 + 白色描边光晕**，让遥控用户
/// 能看到焦点位置；OK/select 键触发 [InkWell] 的默认激活语义。
class TvUpdatePill extends StatefulWidget {
  const TvUpdatePill({super.key});

  @override
  State<TvUpdatePill> createState() => _TvUpdatePillState();
}

class _TvUpdatePillState extends State<TvUpdatePill> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'TvUpdatePill');

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppUpdateState>(
      valueListenable: AppUpdateController.instance,
      builder: (BuildContext context, AppUpdateState state, Widget? _) {
        if (!state.showPill) return const SizedBox.shrink();
        final bool ready = state.phase == AppUpdatePhase.ready || state.phase == AppUpdatePhase.installing;
        final double? progress = state.progress;
        final String label = ready
            ? '更新'
            : progress == null
                ? '更新中'
                : '${(progress * 100).round()}%';
        return Actions(
          actions: <Type, Action<Intent>>{
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                handleTvUpdateTap(context, state);
                return null;
              },
            ),
          },
          child: Focus(
            focusNode: _focusNode,
            // 焦点进入/离开时重建，切换高亮视觉（放大 + 光晕描边）。
            onFocusChange: (_) {
              if (mounted) setState(() {});
            },
            child: Builder(
            builder: (BuildContext context) {
              final bool focused = _focusNode.hasFocus;
              return AnimatedScale(
                scale: focused ? 1.06 : 1.0,
                duration: const Duration(milliseconds: 120),
                child: DecoratedBox(
                  decoration: focused
                      ? BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color: Colors.white.withValues(alpha: 0.85),
                              blurRadius: 14,
                              spreadRadius: 1.5,
                            ),
                          ],
                        )
                      : const BoxDecoration(),
                  child: Material(
                    color: const Color(0xFF2F6BFF),
                    borderRadius: BorderRadius.circular(999),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => handleTvUpdateTap(context, state),
                      focusColor: Colors.white.withValues(alpha: 0.25),
                      hoverColor: Colors.white.withValues(alpha: 0.15),
                      highlightColor: Colors.white.withValues(alpha: 0.3),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            if (ready)
                              const Icon(Icons.download_rounded, size: 20, color: Colors.white)
                            else
                              SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white, value: progress),
                              ),
                            const SizedBox(width: 8),
                            Text(label, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                            if (ready && !state.forceBlocked) ...<Widget>[
                              const SizedBox(width: 8),
                              Container(
                                width: 9,
                                height: 9,
                                decoration: const BoxDecoration(color: Color(0xFFFF4D4F), shape: BoxShape.circle),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
            ),
          ),
        );
      },
    );
  }
}

Future<void> handleTvUpdateTap(BuildContext context, AppUpdateState state) async {
  final AppUpdateController controller = AppUpdateController.instance;
  final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(context);
  if (state.phase != AppUpdatePhase.ready && state.phase != AppUpdatePhase.installing) {
    messenger?.showSnackBar(
      const SnackBar(content: Text('正在后台下载更新，完成后可从这里安装'), behavior: SnackBarBehavior.floating),
    );
    await controller.ensureDownloadedNow();
    return;
  }
  final bool started = await controller.install();
  if (!started) {
    messenger?.showSnackBar(
      const SnackBar(content: Text('无法拉起系统安装器，请检查「安装未知应用」权限'), behavior: SnackBarBehavior.floating),
    );
  }
}

/// 半透明胶囊 Mask 的按键入口。物理键由 Mask 自己处理，悬浮遥控器经此转发。
class CapsuleControlsController {
  CapsuleControlsController._();

  static final CapsuleControlsController instance = CapsuleControlsController._();

  bool Function(LogicalKeyboardKey key)? _handler;

  bool handleKey(LogicalKeyboardKey key) => _handler?.call(key) ?? false;

  void attach(bool Function(LogicalKeyboardKey key) handler) => _handler = handler;

  void detach() => _handler = null;
}

/// 全局半透明操作层：普通模式显示功能胶囊与页面 Tab，儿童模式只构建儿童可用胶囊。
class CapsuleControlsOverlay extends StatefulWidget {
  const CapsuleControlsOverlay({
    super.key,
    required this.visible,
    required this.currentTab,
    required this.onTabSelected,
    required this.onClose,
    required this.onExitRequested,
  });

  final bool visible;
  final int currentTab;
  final ValueChanged<int> onTabSelected;
  final VoidCallback onClose;
  final VoidCallback onExitRequested;

  @override
  State<CapsuleControlsOverlay> createState() => _CapsuleControlsOverlayState();
}

class _CapsuleControlsOverlayState extends State<CapsuleControlsOverlay> {
  final Map<String, FocusNode> _nodes = <String, FocusNode>{};
  List<List<_CapsuleEntry>> _rows = const <List<_CapsuleEntry>>[];
  int _row = 0;
  int _column = 0;
  bool _testOneActive = false;
  bool _testTwoActive = false;

  FocusNode _node(String id) =>
      _nodes.putIfAbsent(id, () => FocusNode(debugLabel: 'capsule-$id'));

  @override
  void initState() {
    super.initState();
    CapsuleControlsController.instance.attach(_handleLogicalKey);
  }

  @override
  void didUpdateWidget(covariant CapsuleControlsOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.visible && widget.visible) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _focusInitial());
    }
  }

  @override
  void dispose() {
    CapsuleControlsController.instance.detach();
    for (final FocusNode node in _nodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _focusInitial() {
    if (!mounted || !widget.visible || _rows.isEmpty) return;
    final bool childMode = ParentalStateController.instance.enabled;
    _row = childMode || widget.currentTab == 0 ? 0 : _rows.length - 1;
    _column = childMode || widget.currentTab == 0 ? 0 : 0;
    _requestCurrent();
  }

  void _requestCurrent() {
    if (_rows.isEmpty) return;
    _row = _row.clamp(0, _rows.length - 1);
    _column = _column.clamp(0, _rows[_row].length - 1);
    _node(_rows[_row][_column].id).requestFocus();
  }

  bool _handleLogicalKey(LogicalKeyboardKey key) {
    if (!widget.visible || _rows.isEmpty) return false;
    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack) {
      widget.onClose();
      return true;
    }
    final bool ok = key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.gameButtonA;
    if (ok) {
      _rows[_row][_column].onActivate();
      return true;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      _column = (_column - 1 + _rows[_row].length) % _rows[_row].length;
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _column = (_column + 1) % _rows[_row].length;
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _row = (_row - 1 + _rows.length) % _rows.length;
      _column = _column.clamp(0, _rows[_row].length - 1);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      _row = (_row + 1) % _rows.length;
      _column = _column.clamp(0, _rows[_row].length - 1);
    } else {
      return true;
    }
    _requestCurrent();
    return true;
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.handled;
    return _handleLogicalKey(event.logicalKey)
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
  }

  void _activateTest(int number) {
    setState(() {
      if (number == 1) {
        _testOneActive = !_testOneActive;
      } else {
        _testTwoActive = !_testTwoActive;
      }
    });
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(
          'capsule_test_ok_message'.tr(
            namedArgs: <String, String>{'__NUMBER__': '$number'},
          ),
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.visible) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: ParentalStateController.instance,
      builder: (context, _) => ValueListenableBuilder<AppUpdateState>(
        valueListenable: AppUpdateController.instance,
        builder: (context, update, _) {
          final bool childMode = ParentalStateController.instance.enabled;
          final List<_CapsuleEntry> allActions = <_CapsuleEntry>[
            _CapsuleEntry(
              id: 'test-1',
              label: (_testOneActive
                      ? 'capsule_test_one_triggered'
                      : 'capsule_test_one')
                  .tr(),
              icon: _testOneActive ? Icons.check_rounded : Icons.gamepad_outlined,
              active: _testOneActive,
              onActivate: () => _activateTest(1),
            ),
            _CapsuleEntry(
              id: 'test-2',
              label: (_testTwoActive
                      ? 'capsule_test_two_triggered'
                      : 'capsule_test_two')
                  .tr(),
              icon: _testTwoActive ? Icons.check_rounded : Icons.tune_rounded,
              active: _testTwoActive,
              onActivate: () => _activateTest(2),
            ),
            if (update.showPill)
              _CapsuleEntry(
                id: 'update',
                label: update.phase == AppUpdatePhase.ready
                    ? 'capsule_install_update'.tr()
                    : 'capsule_download_progress'.tr(
                        namedArgs: <String, String>{
                          '__PROGRESS__':
                              '${((update.progress ?? 0) * 100).round()}',
                        },
                      ),
                icon: update.phase == AppUpdatePhase.ready
                    ? Icons.download_done_rounded
                    : Icons.downloading_rounded,
                onActivate: () => handleTvUpdateTap(context, update),
              ),
          ];
          final List<_CapsuleEntry> actions = allActions
              .where((entry) => entry.isVisible(childMode))
              .toList(growable: false);
          final List<_CapsuleEntry> tabs = <_CapsuleEntry>[
                  _CapsuleEntry(
                    id: 'tab-live',
                    label: 'home_title'.tr(),
                    icon: Icons.live_tv_rounded,
                    audience: _CapsuleAudience.parentOnly,
                    active: widget.currentTab == 0,
                    onActivate: () => widget.onTabSelected(0),
                  ),
                  _CapsuleEntry(
                    id: 'tab-time',
                    label: 'time_title'.tr(),
                    icon: Icons.schedule_rounded,
                    audience: _CapsuleAudience.parentOnly,
                    active: widget.currentTab == 1,
                    onActivate: () => widget.onTabSelected(1),
                  ),
                  _CapsuleEntry(
                    id: 'tab-settings',
                    label: 'profile_title'.tr(),
                    icon: Icons.settings_rounded,
                    audience: _CapsuleAudience.parentOnly,
                    active: widget.currentTab == 2,
                    onActivate: () => widget.onTabSelected(2),
                  ),
                ]
              .where((entry) => entry.isVisible(childMode))
              .toList(growable: false);
          final List<_CapsuleEntry> exitActions = <_CapsuleEntry>[
            _CapsuleEntry(
              id: 'exit-app',
              label: (childMode
                      ? 'capsule_finish_watching'
                      : 'capsule_exit_app')
                  .tr(),
              icon: Icons.power_settings_new_rounded,
              onActivate: widget.onExitRequested,
            ),
          ];
          _rows = <List<_CapsuleEntry>>[
            actions,
            if (tabs.isNotEmpty) tabs,
            exitActions,
          ];
          _row = _row.clamp(0, _rows.length - 1);
          _column = _column.clamp(0, _rows[_row].length - 1);
          return Positioned.fill(
            child: Focus(
              canRequestFocus: false,
              onKeyEvent: _handleKeyEvent,
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.68),
                child: SafeArea(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 20,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          _CapsuleRow(entries: actions, nodeOf: _node),
                          if (tabs.isNotEmpty) ...<Widget>[
                            const SizedBox(height: 28),
                            _CapsuleRow(entries: tabs, nodeOf: _node),
                          ],
                          const SizedBox(height: 28),
                          _CapsuleRow(
                            entries: exitActions,
                            nodeOf: _node,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

enum _CapsuleAudience { everyone, parentOnly, childOnly }

class _CapsuleEntry {
  const _CapsuleEntry({
    required this.id,
    required this.label,
    required this.icon,
    required this.onActivate,
    this.active = false,
    this.audience = _CapsuleAudience.everyone,
  });

  final String id;
  final String label;
  final IconData icon;
  final VoidCallback onActivate;
  final bool active;
  final _CapsuleAudience audience;

  bool isVisible(bool childMode) => switch (audience) {
    _CapsuleAudience.everyone => true,
    _CapsuleAudience.parentOnly => !childMode,
    _CapsuleAudience.childOnly => childMode,
  };
}

class _CapsuleRow extends StatelessWidget {
  const _CapsuleRow({required this.entries, required this.nodeOf});

  final List<_CapsuleEntry> entries;
  final FocusNode Function(String id) nodeOf;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 16,
      runSpacing: 12,
      children: entries
          .map(
            (entry) => _CapsuleButton(
              entry: entry,
              focusNode: nodeOf(entry.id),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _CapsuleButton extends StatefulWidget {
  const _CapsuleButton({required this.entry, required this.focusNode});

  final _CapsuleEntry entry;
  final FocusNode focusNode;

  @override
  State<_CapsuleButton> createState() => _CapsuleButtonState();
}

class _CapsuleButtonState extends State<_CapsuleButton> {
  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (_) {
        if (mounted) setState(() {});
      },
      child: AnimatedScale(
        scale: widget.focusNode.hasFocus ? 1.08 : 1,
        duration: const Duration(milliseconds: 120),
        child: Material(
          color: widget.entry.active
              ? const Color(0xFF16865A)
              : const Color(0xFF263247),
          shape: StadiumBorder(
            side: BorderSide(
              color: widget.focusNode.hasFocus
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.18),
              width: widget.focusNode.hasFocus ? 3 : 1,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: widget.entry.onActivate,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(widget.entry.icon, color: Colors.white, size: 22),
                  const SizedBox(width: 9),
                  Text(
                    widget.entry.label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
