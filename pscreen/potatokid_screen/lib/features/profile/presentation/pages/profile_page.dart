import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:potatokid_screen/features/app/application/bloc/app_bloc.dart';
import 'package:potatokid_screen/features/app/application/bloc/app_event.dart';
import 'package:potatokid_screen/features/app/application/bloc/app_state.dart';
import 'package:potatokid_screen/features/app/application/video_aspect_mode.dart';
import 'package:potatokid_screen/features/iptv/application/bloc/iptv_bloc.dart';
import 'package:potatokid_screen/features/iptv/application/bloc/iptv_event.dart';
import 'package:potatokid_screen/features/profile/application/profile_focus_controller.dart';

/// 支持切换的语言列表（Locale 与翻译文件 key 一一对应）
const List<(Locale, String)> _supportedLanguages = <(Locale, String)>[
  (Locale('zh', 'CN'), 'language_zh_cn'),
  (Locale('zh', 'TW'), 'language_zh_tw'),
  (Locale('en', 'US'), 'language_en_us'),
  (Locale('ja', 'JP'), 'language_ja_jp'),
];

/// 主题的可选值（labelKey 对应翻译文案，mode 对应 [ThemeMode]）
const List<({String labelKey, ThemeMode mode})> _themeOptions =
    <({String labelKey, ThemeMode mode})>[
      (labelKey: 'theme_system', mode: ThemeMode.system),
      (labelKey: 'theme_light', mode: ThemeMode.light),
      (labelKey: 'theme_dark', mode: ThemeMode.dark),
    ];

/// 「我的」Tab 页面：面向 TV 遥控器操作的设置页。
///
/// 布局为「左(选项名) + 空白 + 右(当前值 + 可步进指示 < / >)」的列表行。
/// 选择态由 [ProfileFocusController] 显式驱动：
/// - **上/下**：导航条 ↔ 主题 ↔ 语言 ↔ 悬浮遥控器（由 [MainApp] 路由到控制器）；
/// - **左/右**：仅当焦点在正文列表内时，步进选中行的值（不切顶部 tab）。
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  /// 「刷新频道」行在 [ProfileFocusController.row] 中的序号（最后一行）。
  int get _refreshRow => ProfileFocusController.rowCount - 1;

  /// 刷新状态文案：null=空闲，非空=「刷新中…」/「已刷新」/「刷新失败」。
  final ValueNotifier<String?> _refreshMsg = ValueNotifier<String?>(null);
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    ProfileFocusController.instance.onStepRow = _stepRow;
    ProfileFocusController.instance.onActivateRow = _onActivateRow;
  }

  @override
  void dispose() {
    if (ProfileFocusController.instance.onStepRow == _stepRow) {
      ProfileFocusController.instance.onStepRow = null;
    }
    if (ProfileFocusController.instance.onActivateRow == _onActivateRow) {
      ProfileFocusController.instance.onActivateRow = null;
    }
    _refreshMsg.dispose();
    super.dispose();
  }

  /// OK/触摸激活当前行：仅刷新频道行有动作。
  void _onActivateRow(int row) {
    if (row == _refreshRow && mounted) _refreshChannels();
  }

  /// 触发「刷新频道」：向全局 [IptvBloc] 派发后台刷新，并给出状态反馈。
  void _refreshChannels() {
    if (!mounted || _refreshing) return;
    _refreshing = true;
    _refreshMsg.value = 'settings_refreshing'.tr();
    final Completer<bool> done = Completer<bool>();
    context.read<IptvBloc>().add(LoadIptv(isRefresh: true, completer: done));
    unawaited(done.future.then((bool ok) {
      if (!mounted) return;
      _refreshing = false;
      _refreshMsg.value =
          ok ? 'settings_refresh_done'.tr() : 'settings_refresh_failed'.tr();
      // 几秒后恢复空闲，便于再次操作。
      Timer(const Duration(seconds: 2), () {
        if (mounted && !_refreshing) _refreshMsg.value = null;
      });
    }));
  }

  /// 按当前行执行真正的值改动（主题/语言/悬浮遥控器/硬解/刷新频道）。
  void _stepRow(int row, int delta) {
    if (!mounted) return;
    switch (row) {
      case 0: // 主题
        final AppState state = context.read<AppBloc>().state;
        final int idx = _themeOptions.indexWhere(
          (t) => t.mode == state.themeMode,
        );
        final int val = idx < 0 ? 0 : idx;
        final int next = (val + delta).clamp(0, _themeOptions.length - 1);
        context.read<AppBloc>().add(ChangeThemeMode(_themeOptions[next].mode));
        break;
      case 1: // 语言
        final int idx = _supportedLanguages.indexWhere(
          (l) => context.locale == l.$1,
        );
        final int val = idx < 0 ? 0 : idx;
        final int next = (val + delta).clamp(0, _supportedLanguages.length - 1);
        context.setLocale(_supportedLanguages[next].$1);
        break;
      case 2: // 悬浮遥控器：当前开(idx0)则改关，否则改开
        final bool isOn = context.read<AppBloc>().state.showFloatingRemote;
        context.read<AppBloc>().add(SetFloatingRemote(!isOn));
        break;
      case 3: // 启用硬解：开/关切换
        final bool hwdec = context.read<AppBloc>().state.hwdecEnabled;
        context.read<AppBloc>().add(SetHardwareDecode(!hwdec));
        break;
      case 4: // 画面：原始/拉伸/16:9/4:3/21:9 步进
        final List<VideoAspectMode> opts = VideoAspectMode.values;
        final int cur = opts.indexOf(context.read<AppBloc>().state.aspectMode);
        final int val = cur < 0 ? 0 : cur;
        final int next = (val + delta).clamp(0, opts.length - 1);
        context.read<AppBloc>().add(ChangeAspectMode(opts[next]));
        break;
      case 5: // 刷新频道（左/右键按下同样触发）
        _refreshChannels();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surface,
      child: ListenableBuilder(
        listenable: ProfileFocusController.instance,
        builder: (context, _) {
          final ProfileFocusController c = ProfileFocusController.instance;
          final bool inContent = c.focused;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 80, 20, 20),
            children: <Widget>[
              _buildThemeRow(inContent, c),
              const SizedBox(height: 12),
              _buildLanguageRow(inContent, c),
              const SizedBox(height: 12),
              _buildRemoteRow(inContent, c),
              const SizedBox(height: 12),
              _buildHwdecRow(inContent, c),
              const SizedBox(height: 12),
              _buildAspectRow(inContent, c),
              const SizedBox(height: 12),
              _buildRefreshRow(inContent, c),
            ],
          );
        },
      ),
    );
  }

  Widget _buildThemeRow(bool inContent, ProfileFocusController c) {
    return BlocBuilder<AppBloc, AppState>(
      builder: (context, state) {
        final int idx = _themeOptions.indexWhere(
          (t) => t.mode == state.themeMode,
        );
        final int val = idx < 0 ? 0 : idx;
        return _SettingRow(
          highlighted: inContent && c.row == 0,
          label: 'theme_mode_title'.tr(),
          value: _themeOptions[val].labelKey.tr(),
          canStepLeft: val > 0,
          canStepRight: val < _themeOptions.length - 1,
          onTap: () => c.select(0),
          onStepLeft: () {
            c.select(0);
            c.step(-1);
          },
          onStepRight: () {
            c.select(0);
            c.step(1);
          },
        );
      },
    );
  }

  Widget _buildLanguageRow(bool inContent, ProfileFocusController c) {
    final int idx = _supportedLanguages.indexWhere(
      (l) => context.locale == l.$1,
    );
    final int val = idx < 0 ? 0 : idx;
    return _SettingRow(
      highlighted: inContent && c.row == 1,
      label: 'language_mode_title'.tr(),
      value: _supportedLanguages[val].$2.tr(),
      canStepLeft: val > 0,
      canStepRight: val < _supportedLanguages.length - 1,
      onTap: () => c.select(1),
      onStepLeft: () {
        c.select(1);
        c.step(-1);
      },
      onStepRight: () {
        c.select(1);
        c.step(1);
      },
    );
  }

  Widget _buildRemoteRow(bool inContent, ProfileFocusController c) {
    return BlocBuilder<AppBloc, AppState>(
      builder: (context, state) {
        // 悬浮遥控器：开(idx0) | 关(idx1)
        final bool isOn = state.showFloatingRemote;
        return _SettingRow(
          highlighted: inContent && c.row == 2,
          label: 'settings_floating_remote'.tr(),
          value: isOn ? 'common_on'.tr() : 'common_off'.tr(),
          canStepLeft: isOn,
          canStepRight: !isOn,
          onTap: () => c.select(2),
          onStepLeft: () {
            c.select(2);
            c.step(-1);
          },
          onStepRight: () {
            c.select(2);
            c.step(1);
          },
        );
      },
    );
  }

  Widget _buildHwdecRow(bool inContent, ProfileFocusController c) {
    return BlocBuilder<AppBloc, AppState>(
      builder: (context, state) {
        // 启用硬解：开 | 关
        final bool isOn = state.hwdecEnabled;
        return _SettingRow(
          highlighted: inContent && c.row == 3,
          label: 'settings_hwdec'.tr(),
          value: isOn ? 'common_on'.tr() : 'common_off'.tr(),
          canStepLeft: isOn,
          canStepRight: !isOn,
          onTap: () => c.select(3),
          onStepLeft: () {
            c.select(3);
            c.step(-1);
          },
          onStepRight: () {
            c.select(3);
            c.step(1);
          },
        );
      },
    );
  }

  /// 「画面」行：原始/拉伸/16:9/4:3/21:9 步进。
  Widget _buildAspectRow(bool inContent, ProfileFocusController c) {
    final List<VideoAspectMode> options = VideoAspectMode.values;
    return BlocBuilder<AppBloc, AppState>(
      builder: (context, state) {
        final int cur = options.indexOf(state.aspectMode);
        final int val = cur < 0 ? 0 : cur;
        return _SettingRow(
          highlighted: inContent && c.row == 4,
          label: 'video_aspect'.tr(),
          value: options[val].labelKey.tr(),
          canStepLeft: val > 0,
          canStepRight: val < options.length - 1,
          onTap: () => c.select(4),
          onStepLeft: () {
            c.select(4);
            c.step(-1);
          },
          onStepRight: () {
            c.select(4);
            c.step(1);
          },
        );
      },
    );
  }

  /// 「刷新频道」行：按下右箭头 / OK / 触摸即重新拉取线上频道列表。
  Widget _buildRefreshRow(bool inContent, ProfileFocusController c) {
    return ListenableBuilder(
      listenable: _refreshMsg,
      builder: (context, _) {
        final bool busy = _refreshing;
        return _SettingRow(
          highlighted: inContent && c.row == _refreshRow,
          label: 'settings_refresh_channels'.tr(),
          value: _refreshMsg.value ?? '',
          canStepLeft: false,
          canStepRight: !busy,
          onTap: () => c.select(_refreshRow),
          onStepLeft: () => c.select(_refreshRow),
          onStepRight: () {
            c.select(_refreshRow);
            _refreshChannels();
          },
        );
      },
    );
  }
}

/// 单行设置项：左侧选项名 + 中间空白 + 右侧当前值与步进指示（< 值 >）。
///
/// 选中行高亮；触摸/点击可直接移动选择并步进。具体改值由
/// [ProfileFocusController.onStepRow]（即 [ProfilePage]）执行。
class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.highlighted,
    required this.label,
    required this.value,
    required this.canStepLeft,
    required this.canStepRight,
    required this.onTap,
    required this.onStepLeft,
    required this.onStepRight,
  });

  final bool highlighted;
  final String label;
  final String value;
  final bool canStepLeft;
  final bool canStepRight;
  final VoidCallback onTap;
  final VoidCallback onStepLeft;
  final VoidCallback onStepRight;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme textTheme = Theme.of(context).textTheme;
    final Color accent = highlighted ? scheme.primary : scheme.onSurfaceVariant;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: highlighted
              ? scheme.primaryContainer.withValues(alpha: 0.30)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: highlighted ? scheme.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          children: <Widget>[
            Text(
              label,
              style: textTheme.titleMedium?.copyWith(
                color: highlighted ? scheme.onSurface : scheme.onSurfaceVariant,
              ),
            ),
            const Spacer(),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (canStepLeft)
                  _StepIcon(
                    icon: Icons.chevron_left,
                    color: accent,
                    onTap: onStepLeft,
                  ),
                Text(
                  value,
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: accent,
                  ),
                ),
                if (canStepRight)
                  _StepIcon(
                    icon: Icons.chevron_right,
                    color: accent,
                    onTap: onStepRight,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 步进指示图标（< 或 >），触摸/点击也可直接步进。
class _StepIcon extends StatelessWidget {
  const _StepIcon({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Icon(icon, color: color, size: 24),
      ),
    );
  }
}
