import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pscreen_screen/app/config/app_config.dart';
import 'package:potatokid_screen/core/di/injection.dart';
import 'package:pscreen_screen/core/logging/log_service.dart';
import 'package:pscreen_screen/core/utils/app_settings.dart';
import 'package:pscreen_screen/core/utils/app_version.dart';
import 'package:potatokid_screen/features/app/application/bloc/app_bloc.dart';
import 'package:potatokid_screen/features/app/application/bloc/app_event.dart';
import 'package:potatokid_screen/features/app/application/bloc/app_state.dart';
import 'package:pscreen_screen/core/media/video_aspect_mode.dart';
import 'package:pscreen_screen/core/media/sleep_timer_controller.dart';
import 'package:pscreen_screen/features/iptv/application/bloc/iptv_bloc.dart';
import 'package:pscreen_screen/features/iptv/application/bloc/iptv_event.dart';
import 'package:pscreen_screen/features/iptv/application/channel_failure_guard.dart';
import 'package:pscreen_screen/features/msg/application/message_overlay_controller.dart';
import 'package:potatokid_screen/features/msg/presentation/widgets/message_overlay.dart';
import 'package:potatokid_screen/features/profile/application/profile_focus_controller.dart';
import 'package:pscreen_screen/features/weather/application/bloc/weather_bloc.dart';
import 'package:pscreen_screen/features/weather/application/bloc/weather_event.dart';
import 'package:pscreen_screen/features/remote/application/bloc/remote_login_bloc.dart';
import 'package:pscreen_screen/features/remote/application/bloc/remote_login_event.dart';
import 'package:pscreen_screen/features/remote/application/bloc/remote_login_state.dart';
import 'package:potatokid_screen/shared/widgets/confirm_dialog.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:restart_app/restart_app.dart';

/// 支持切换的语言列表（Locale 与翻译文件 key 一一对应）
const List<(Locale, String)> _supportedLanguages = <(Locale, String)>[
  (Locale('zh', 'CN'), 'language_zh_cn'),
  (Locale('zh', 'TW'), 'language_zh_tw'),
  (Locale('en', 'US'), 'language_en_us'),
  (Locale('ja', 'JP'), 'language_ja_jp'),
];

/// 主题的可选值（labelKey 对应翻译文案，mode 对应 [ThemeMode]）
const List<({String labelKey, ThemeMode mode})> _themeOptions = <({String labelKey, ThemeMode mode})>[
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

  /// 当前处于行内输入编辑态的行号；null = 未编辑（跨组件静态信号）。
  ///
  /// 悬浮遥控器按键不经过 Flutter 焦点链（[MainApp] 的 FloatingRemote.onKey
  /// 直调 `_handleLogical`），页面级 Focus 拦截不到，故壳层在返回/OK 分支
  /// 优先读取此信号；物理/蓝牙遥控器仍由页面 Focus 先拦截（见
  /// `_ProfilePageState._handlePageKey`）。
  static int? editingRow;

  /// 是否有行处于行内输入编辑态。
  static bool get isInlineEditing => editingRow != null;

  /// 取消行内输入编辑（由 [_ProfilePageState] 挂接，供悬浮遥控器返回键触发）。
  static VoidCallback? onCancelInlineEdit;

  /// 提交行内输入编辑（由 [_ProfilePageState] 挂接，供悬浮遥控器 OK 键触发）。
  static Future<void> Function()? onSubmitInlineEdit;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  /// 「定时关闭」行在 [ProfileFocusController.row] 中的序号。
  static const int _sleepTimerRow = 6;

  /// 「后台播放」行在 [ProfileFocusController.row] 中的序号。
  static const int _backgroundPlaybackRow = 7;

  /// 「刷新频道」行在 [ProfileFocusController.row] 中的序号。
  static const int _refreshRow = 8;

  /// 「清理失效源」行在 [ProfileFocusController.row] 中的序号。
  static const int _removeInvalidRow = 9;

  /// 「复制失效源」行（只读动作行：按 OK 把已记录的失效地址复制到剪贴板）的序号。
  static const int _copyInvalidRow = 10;

  /// 「代理重试」行在 [ProfileFocusController.row] 中的序号。
  static const int _proxyRetryRow = 11;

  /// 「重置」行（清空全部持久化缓存并重启应用）的序号。
  static const int _resetRow = 12;

  /// 「远程」行（实时通道账号登录：常态展示账号+状态，激活后行内输入框）的序号。
  static const int _remoteRow = 13;

  /// 「版本」行（只读说明行，展示 `v1.0.0+1`，值来自平台打包信息）。
  static const int _versionRow = ProfileFocusController.rowCount - 3;

  /// 「天气数据来源」行（只读说明行）。
  static const int _weatherSourceRow = ProfileFocusController.rowCount - 2;

  /// 「免责声明」行（只读说明行，文案最长，放最后一行）。
  static const int _disclaimerRow = ProfileFocusController.rowCount - 1;

  /// 切换天气城市后延迟生效的时间：5 秒内再次变更则重新计时，以最后一次为准。
  static const Duration _cityApplyDelay = Duration(seconds: 5);

  /// 天气城市的可选项：首项空串代表「自动」（IP 反查），
  /// 其余为 `.env` 中 `WEATHER_CITIES` 配置的城市名。
  static List<String> get _weatherCityOptions => <String>['', ...AppConfig.weatherCities];

  /// 天气城市选项的展示文案：空串为「自动」，其余直接显示城市名。
  static String _weatherCityLabel(String city) => city.isEmpty ? 'weather_city_auto'.tr() : city;

  /// 定时关闭选项的展示文案：null 为「关闭」，其余显示「N 分钟」。
  static String _sleepTimerLabel(int? minutes) =>
      minutes == null ? 'common_off'.tr() : 'sleep_timer_minutes'.tr(args: <String>['$minutes']);

  /// 刷新状态文案：null=空闲，非空=「刷新中…」/「已刷新」/「刷新失败」。
  final ValueNotifier<String?> _refreshMsg = ValueNotifier<String?>(null);
  bool _refreshing = false;

  /// 复制失效源的结果提示：null=空闲，非空=「已复制 N 条」/「暂无失效源记录」。
  final ValueNotifier<String?> _copyMsg = ValueNotifier<String?>(null);
  Timer? _copyMsgTimer;

  /// 重置流程是否正在进行（含确认弹窗），避免重复触发/叠出多个弹窗。
  bool _resetting = false;

  /// 当前行内编辑行号：真值源为 [ProfilePage.editingRow]
  /// （跨组件静态信号，悬浮遥控器直调路径读取）。
  int? get _editingRow => ProfilePage.editingRow;
  set _editingRow(int? value) => ProfilePage.editingRow = value;

  /// 「远程」行输入框的控制器与焦点节点。
  final TextEditingController _remoteInputController = TextEditingController();
  final FocusNode _remoteInputFocusNode = FocusNode();

  Timer? _cityApplyTimer;

  /// 各设置行的 GlobalKey：用于「选中行滚动入屏」。
  final List<GlobalKey> _rowKeys = List<GlobalKey>.generate(ProfileFocusController.rowCount, (_) => GlobalKey<State>());

  int _prevRow = 0;
  bool _prevFocused = false;

  @override
  void initState() {
    super.initState();
    ProfileFocusController.instance.onStepRow = _stepRow;
    ProfileFocusController.instance.onActivateRow = _onActivateRow;
    ProfileFocusController.instance.addListener(_onFocusChanged);
    ProfilePage.onCancelInlineEdit = _cancelInlineEdit;
    ProfilePage.onSubmitInlineEdit = _submitInlineEdit;
    // 冷启动：AppSettings 异步加载完成后强制重建一次，保证密码掩码/未设置
    // 展示与持久化值一致（本行不走 BlocBuilder，自行兜底）。
    AppSettings.instance.ensureLoaded().whenComplete(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    ProfileFocusController.instance.removeListener(_onFocusChanged);
    if (ProfileFocusController.instance.onStepRow == _stepRow) {
      ProfileFocusController.instance.onStepRow = null;
    }
    if (ProfileFocusController.instance.onActivateRow == _onActivateRow) {
      ProfileFocusController.instance.onActivateRow = null;
    }
    if (ProfilePage.onCancelInlineEdit == _cancelInlineEdit) {
      ProfilePage.onCancelInlineEdit = null;
    }
    if (ProfilePage.onSubmitInlineEdit == _submitInlineEdit) {
      ProfilePage.onSubmitInlineEdit = null;
    }
    // 防御：编辑态中被销毁时复位静态信号，避免残留值卡住壳层按键。
    ProfilePage.editingRow = null;
    _cityApplyTimer?.cancel();
    _copyMsgTimer?.cancel();
    _copyMsg.dispose();
    _remoteInputController.dispose();
    _remoteInputFocusNode.dispose();
    super.dispose();
  }

  /// 安排天气城市生效：取消上一次计时，5 秒后无新变更才真正重新拉取天气。
  ///
  /// 防止连续按左/右键步进城市时每档都发一次请求。
  void _scheduleCityApply() {
    _cityApplyTimer?.cancel();
    _cityApplyTimer = Timer(_cityApplyDelay, () {
      if (!mounted) return;
      context.read<WeatherBloc>().add(const LoadWeather());
    });
  }

  /// 焦点或行号变化时，让选中行滚入可视区，避免被屏幕边缘裁切。
  void _onFocusChanged() {
    final ProfileFocusController c = ProfileFocusController.instance;
    // 焦点离开编辑中的行时取消输入编辑态（不提交）。
    if (_editingRow != null && c.row != _editingRow) {
      _cancelInlineEdit();
    }
    if (!c.focused) return;
    if (c.row == _prevRow && _prevFocused) return;
    _prevRow = c.row;
    _prevFocused = c.focused;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final BuildContext? ctx = _rowKeys[c.row].currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(ctx, alignment: 0.5, duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
    });
  }

  /// OK/触摸激活当前行：刷新频道行、复制失效源行与重置行有动作。
  void _onActivateRow(int row) {
    if (row == _refreshRow && mounted) _refreshChannels();
    if (row == _copyInvalidRow && mounted) _copyInvalidSources();
    if (row == _resetRow && mounted) _resetAll();
    if (row == _remoteRow && mounted) _beginInlineEdit(_remoteRow);
  }

  /// 「重置」：先二次确认，确认后清空全部持久化缓存并重启应用。
  ///
  /// 重启说明（restart_app）：
  /// - Android 默认重启只重建 Activity，**进程可能保留**，内存里的单例
  ///   （AppSettings/Bloc/缓存）不会回到默认值；因此这里用
  ///   [RestartMode.process] + `forceKill: true` 让插件先拉起新 Activity、
  ///   再结束旧进程（插件内部执行 `Runtime.exit(0)`），实现真正的冷启动；
  /// - 插件返回失败（无启动 Activity、launch intent 解析失败等）或异常时，
  ///   退化为 [SystemNavigator.pop] 结束应用——用户下次进入即为干净状态，
  ///   满足「无法重启则退出程序」的要求。
  Future<void> _resetAll() async {
    if (!mounted || _resetting) return;
    _resetting = true;
    bool confirmed = false;
    try {
      confirmed = await ConfirmDialog.show(
        context,
        title: 'settings_reset_title'.tr(),
        message: 'settings_reset_message'.tr(),
        cancelLabel: 'settings_reset_cancel'.tr(),
        confirmLabel: 'settings_reset_ok'.tr(),
      );
    } finally {
      _resetting = false;
    }
    if (!confirmed || !mounted) return;

    Injection.get<LogService>().info('[ProfilePage] 重置：开始清空全部持久化缓存');
    // 1) 清空所有持久化缓存（当前全部落在 SharedPreferences），并复位内存设置。
    await AppSettings.instance.clearAllPersisted();

    // 2) 重启应用；失败则退出程序。
    try {
      final RestartResult result = await Restart.restartApp(mode: RestartMode.process, forceKill: true);
      Injection.get<LogService>().info(
        '[ProfilePage] 重置：重启结果 success=${result.success} '
        'mode=${result.mode.name} code=${result.code} message=${result.message}',
      );
      if (result.success) return;
    } catch (e) {
      Injection.get<LogService>().error('[ProfilePage] 重置：重启异常', error: e);
    }
    // 走到这里说明没能重启：直接结束应用（下次进入即为默认设置）。
    await SystemNavigator.pop();
  }

  /// 触发「刷新频道」：向全局 [IptvBloc] 派发后台刷新，并给出状态反馈。
  void _refreshChannels() {
    if (!mounted || _refreshing) return;
    _refreshing = true;
    _refreshMsg.value = 'settings_refreshing'.tr();
    final Completer<bool> done = Completer<bool>();
    context.read<IptvBloc>().add(LoadIptv(isRefresh: true, completer: done));
    unawaited(
      done.future.then((bool ok) {
        if (!mounted) return;
        _refreshing = false;
        _refreshMsg.value = ok ? 'settings_refresh_done'.tr() : 'settings_refresh_failed'.tr();
        // 几秒后恢复空闲，便于再次操作。
        Timer(const Duration(seconds: 2), () {
          if (mounted && !_refreshing) _refreshMsg.value = null;
        });
      }),
    );
  }

  /// 按当前行执行真正的值改动（主题/语言/悬浮遥控器/硬解/画面/天气城市/刷新频道/清理失效源）。
  void _stepRow(int row, int delta) {
    if (!mounted) return;
    switch (row) {
      case 0: // 主题
        final AppState state = context.read<AppBloc>().state;
        final int idx = _themeOptions.indexWhere((t) => t.mode == state.themeMode);
        final int val = idx < 0 ? 0 : idx;
        final int next = (val + delta).clamp(0, _themeOptions.length - 1);
        context.read<AppBloc>().add(ChangeThemeMode(_themeOptions[next].mode));
        break;
      case 1: // 语言
        final int idx = _supportedLanguages.indexWhere((l) => context.locale == l.$1);
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
      case 5: // 天气城市：自动 → .env 配置的城市 步进（5 秒后生效）
        final List<String> opts = _weatherCityOptions;
        final int cur = opts.indexOf(context.read<AppBloc>().state.weatherCity);
        final int val = cur < 0 ? 0 : cur;
        final int next = (val + delta).clamp(0, opts.length - 1);
        context.read<AppBloc>().add(ChangeWeatherCity(opts[next]));
        _scheduleCityApply();
        break;
      case _sleepTimerRow: // 定时关闭：关闭 → 5 → 10 → … → 90 分钟步进
        final List<int?> opts = SleepTimerController.options;
        final int cur = opts.indexOf(SleepTimerController.instance.minutes);
        final int val = cur < 0 ? 0 : cur;
        final int next = (val + delta).clamp(0, opts.length - 1);
        SleepTimerController.instance.setMinutes(opts[next]);
        break;
      case _backgroundPlaybackRow: // 后台播放：开/关切换
        final bool isOn = context.read<AppBloc>().state.backgroundPlayback;
        context.read<AppBloc>().add(SetBackgroundPlayback(!isOn));
        break;
      case _refreshRow: // 刷新频道（左/右键按下同样触发）
        _refreshChannels();
        break;
      case _removeInvalidRow: // 清理失效源：开/关切换（切换后按新开关重算频道列表）
        final bool isOn = context.read<AppBloc>().state.removeInvalidSources;
        context.read<AppBloc>().add(SetRemoveInvalidSources(!isOn));
        context.read<IptvBloc>().add(FilterInvalidChannels(!isOn));
        break;
      case _proxyRetryRow: // 代理重试：开/关切换
        final bool isOn = context.read<AppBloc>().state.proxyRetryEnabled;
        context.read<AppBloc>().add(SetProxyRetry(!isOn));
        break;
      case _resetRow: // 重置（右/左/OK 均触发确认弹窗）
        _resetAll();
        break;
      case _remoteRow: // 远程：左/右键打开行内输入框
        _beginInlineEdit(_remoteRow);
        break;
      case _copyInvalidRow: // 复制失效源：只读动作行，仅 OK（activate）触发复制
        break;
      case _disclaimerRow: // 免责声明：只读说明，无值可切换
        break;
      case _versionRow: // 版本：只读说明，无值可切换
        break;
      case _weatherSourceRow: // 天气数据来源：只读说明，无值可切换
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Focus(
      onKeyEvent: _handlePageKey,
      child: ColoredBox(
        color: scheme.surface,
        child: ListenableBuilder(
          listenable: ProfileFocusController.instance,
          builder: (context, _) {
            final ProfileFocusController c = ProfileFocusController.instance;
            final bool inContent = c.focused;
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 80, 20, 20),
              children: <Widget>[
                KeyedSubtree(key: _rowKeys[0], child: _buildThemeRow(inContent, c)),
                const SizedBox(height: 12),
                KeyedSubtree(key: _rowKeys[1], child: _buildLanguageRow(inContent, c)),
                const SizedBox(height: 12),
                KeyedSubtree(key: _rowKeys[2], child: _buildRemoteRow(inContent, c)),
                const SizedBox(height: 12),
                KeyedSubtree(key: _rowKeys[3], child: _buildHwdecRow(inContent, c)),
                const SizedBox(height: 12),
                KeyedSubtree(key: _rowKeys[4], child: _buildAspectRow(inContent, c)),
                const SizedBox(height: 12),
                KeyedSubtree(key: _rowKeys[5], child: _buildWeatherCityRow(inContent, c)),
                const SizedBox(height: 12),
                KeyedSubtree(key: _rowKeys[_sleepTimerRow], child: _buildSleepTimerRow(inContent, c)),
                const SizedBox(height: 12),
                KeyedSubtree(key: _rowKeys[_backgroundPlaybackRow], child: _buildBackgroundPlaybackRow(inContent, c)),
                const SizedBox(height: 12),
                KeyedSubtree(key: _rowKeys[_refreshRow], child: _buildRefreshRow(inContent, c)),
                const SizedBox(height: 12),
                KeyedSubtree(key: _rowKeys[_removeInvalidRow], child: _buildRemoveInvalidRow(inContent, c)),
                const SizedBox(height: 12),
                KeyedSubtree(key: _rowKeys[_copyInvalidRow], child: _buildCopyInvalidRow(inContent, c)),
                const SizedBox(height: 12),
                KeyedSubtree(key: _rowKeys[_proxyRetryRow], child: _buildProxyRetryRow(inContent, c)),
                const SizedBox(height: 12),
                KeyedSubtree(key: _rowKeys[_resetRow], child: _buildResetRow(inContent, c)),
                const SizedBox(height: 12),
                KeyedSubtree(key: _rowKeys[_remoteRow], child: _buildRemoteLoginRow(inContent, c)),
                const SizedBox(height: 12),
                KeyedSubtree(key: _rowKeys[_versionRow], child: _buildVersionRow(inContent, c)),
                const SizedBox(height: 12),
                KeyedSubtree(key: _rowKeys[_weatherSourceRow], child: _buildWeatherSourceRow(inContent, c)),
                const SizedBox(height: 12),
                KeyedSubtree(key: _rowKeys[_disclaimerRow], child: _buildDisclaimerRow(inContent, c)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildThemeRow(bool inContent, ProfileFocusController c) {
    return BlocBuilder<AppBloc, AppState>(
      builder: (context, state) {
        final int idx = _themeOptions.indexWhere((t) => t.mode == state.themeMode);
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
    final int idx = _supportedLanguages.indexWhere((l) => context.locale == l.$1);
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

  /// 「天气城市」行：自动（IP 反查）→ `.env` 配置的城市 步进。
  ///
  /// 改动会在 5 秒后统一生效（见 [_scheduleCityApply]）。
  Widget _buildWeatherCityRow(bool inContent, ProfileFocusController c) {
    final List<String> options = _weatherCityOptions;
    return BlocBuilder<AppBloc, AppState>(
      builder: (context, state) {
        final int cur = options.indexOf(state.weatherCity);
        final int val = cur < 0 ? 0 : cur;
        return _SettingRow(
          highlighted: inContent && c.row == 5,
          label: 'weather_city'.tr(),
          value: _weatherCityLabel(options[val]),
          canStepLeft: val > 0,
          canStepRight: val < options.length - 1,
          onTap: () => c.select(5),
          onStepLeft: () {
            c.select(5);
            c.step(-1);
          },
          onStepRight: () {
            c.select(5);
            c.step(1);
          },
        );
      },
    );
  }

  /// 「定时关闭」行：关闭 / 5~90 分钟步进。
  ///
  /// 选中非「关闭」后立即开始按秒倒计时，首页左上角实时显示剩余时间，
  /// 到点自动退出应用（见 [SleepTimerController]）。监听控制器以同步显示当前倒计时。
  Widget _buildSleepTimerRow(bool inContent, ProfileFocusController c) {
    return ListenableBuilder(
      listenable: SleepTimerController.instance,
      builder: (context, _) {
        final List<int?> options = SleepTimerController.options;
        final int cur = options.indexOf(SleepTimerController.instance.minutes);
        final int val = cur < 0 ? 0 : cur;
        return _SettingRow(
          highlighted: inContent && c.row == _sleepTimerRow,
          label: 'settings_sleep_timer'.tr(),
          value: _sleepTimerLabel(options[val]),
          canStepLeft: val > 0,
          canStepRight: val < options.length - 1,
          onTap: () => c.select(_sleepTimerRow),
          onStepLeft: () {
            c.select(_sleepTimerRow);
            c.step(-1);
          },
          onStepRight: () {
            c.select(_sleepTimerRow);
            c.step(1);
          },
        );
      },
    );
  }

  /// 「后台播放」行：开/关切换（默认关）。
  ///
  /// 关闭时保持 media_kit 默认行为——App 退到后台即暂停；
  /// 开启后退到后台/息屏不暂停，声音继续播放。
  Widget _buildBackgroundPlaybackRow(bool inContent, ProfileFocusController c) {
    return BlocBuilder<AppBloc, AppState>(
      builder: (context, state) {
        final bool isOn = state.backgroundPlayback;
        return _SettingRow(
          highlighted: inContent && c.row == _backgroundPlaybackRow,
          label: 'settings_background_playback'.tr(),
          value: isOn ? 'common_on'.tr() : 'common_off'.tr(),
          canStepLeft: isOn,
          canStepRight: !isOn,
          onTap: () => c.select(_backgroundPlaybackRow),
          onStepLeft: () {
            c.select(_backgroundPlaybackRow);
            c.step(-1);
          },
          onStepRight: () {
            c.select(_backgroundPlaybackRow);
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

  /// 「清理失效源」行：开/关切换。
  ///
  /// 开启后，同一频道连续 5 次「明确打不开」（覆盖全部源）时会先探测确认，
  /// 确属失效的地址记入持久化黑名单并从列表移除；关闭后列表恢复完整。
  Widget _buildRemoveInvalidRow(bool inContent, ProfileFocusController c) {
    return BlocBuilder<AppBloc, AppState>(
      builder: (context, state) {
        final bool isOn = state.removeInvalidSources;
        return _SettingRow(
          highlighted: inContent && c.row == _removeInvalidRow,
          label: 'settings_remove_invalid'.tr(),
          value: isOn ? 'common_on'.tr() : 'common_off'.tr(),
          canStepLeft: isOn,
          canStepRight: !isOn,
          onTap: () => c.select(_removeInvalidRow),
          onStepLeft: () {
            c.select(_removeInvalidRow);
            c.step(-1);
          },
          onStepRight: () {
            c.select(_removeInvalidRow);
            c.step(1);
          },
        );
      },
    );
  }

  /// 「复制失效源」行：只读动作行（无左右步进）。
  ///
  /// 按 OK（或触摸）把「清理失效源」已记录的失效地址复制到剪贴板，便于调试排查；
  /// 右侧显示复制结果（「已复制 N 条」/「暂无失效源记录」），2 秒后恢复空闲。
  /// 数据来自 [ChannelFailureGuard] 的持久化记录（键 `iptv_invalid_sources_v1`）。
  Widget _buildCopyInvalidRow(bool inContent, ProfileFocusController c) {
    return ListenableBuilder(
      listenable: _copyMsg,
      builder: (context, _) => _SettingRow(
        highlighted: inContent && c.row == _copyInvalidRow,
        label: 'settings_copy_invalid'.tr(),
        value: _copyMsg.value ?? '',
        canStepLeft: false,
        canStepRight: false,
        // 触摸/点击行即复制；遥控器按 OK 走 [ProfileFocusController.activate]。
        onTap: () {
          c.select(_copyInvalidRow);
          _copyInvalidSources();
        },
        onStepLeft: () => c.select(_copyInvalidRow),
        onStepRight: () => c.select(_copyInvalidRow),
      ),
    );
  }

  /// 把已记录的失效地址复制到剪贴板（每行一个，便于直接粘贴排查）。
  Future<void> _copyInvalidSources() async {
    final ChannelFailureGuard guard = ChannelFailureGuard.instance;
    await guard.ensureLoaded();
    if (!mounted) return;
    final List<String> urls = guard.invalidUrls.toList(growable: false);
    final LogService log = Injection.get<LogService>();
    if (urls.isEmpty) {
      log.info('[ProfilePage] 复制失效源：暂无记录');
      _showCopyMsg('settings_copy_invalid_empty'.tr());
      return;
    }
    await Clipboard.setData(ClipboardData(text: urls.join('\n')));
    if (!mounted) return;
    log.info('[ProfilePage] 已复制 ${urls.length} 个失效地址到剪贴板');
    _showCopyMsg('settings_copy_invalid_done'.tr(args: <String>['${urls.length}']));
  }

  /// 显示复制结果提示，2 秒后恢复空闲（与「刷新频道」的提示节奏一致）。
  void _showCopyMsg(String msg) {
    _copyMsgTimer?.cancel();
    _copyMsg.value = msg;
    _copyMsgTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) _copyMsg.value = null;
    });
  }

  /// 「代理重试」行：开/关切换。
  ///
  /// 开启后，直连打不开/卡死的源会改用免费代理池（proxy.scdn.io）里的 HTTP 代理
  /// 重试一次同一个源；代理也失败才换下一个源。
  Widget _buildProxyRetryRow(bool inContent, ProfileFocusController c) {
    return BlocBuilder<AppBloc, AppState>(
      builder: (context, state) {
        final bool isOn = state.proxyRetryEnabled;
        return _SettingRow(
          highlighted: inContent && c.row == _proxyRetryRow,
          label: 'settings_proxy_retry'.tr(),
          value: isOn ? 'common_on'.tr() : 'common_off'.tr(),
          canStepLeft: isOn,
          canStepRight: !isOn,
          onTap: () => c.select(_proxyRetryRow),
          onStepLeft: () {
            c.select(_proxyRetryRow);
            c.step(-1);
          },
          onStepRight: () {
            c.select(_proxyRetryRow);
            c.step(1);
          },
        );
      },
    );
  }

  /// 「重置」行：与「刷新频道」同样是按钮行，按下右箭头 / OK / 触摸即触发。
  ///
  /// 区别在于**必须先二次确认**（是否重置所有选项？重置后将退出应用。），
  /// 确认后清空全部持久化缓存并重启应用（无法重启则退出应用）。
  Widget _buildResetRow(bool inContent, ProfileFocusController c) {
    return _SettingRow(
      highlighted: inContent && c.row == _resetRow,
      label: 'settings_reset'.tr(),
      value: '',
      canStepLeft: false,
      canStepRight: !_resetting,
      onTap: () => c.select(_resetRow),
      onStepLeft: () => c.select(_resetRow),
      onStepRight: () {
        c.select(_resetRow);
        _resetAll();
      },
    );
  }

  /// 「远程」行：常态展示账号与登录状态（`ABCD 正在登录`），点击 `>` / OK /
  /// 左右键进入行内输入；编辑态替换为输入框（见 [_buildRemoteEditRow]）。
  Widget _buildRemoteLoginRow(bool inContent, ProfileFocusController c) {
    return BlocBuilder<RemoteLoginBloc, RemoteLoginState>(
      builder: (context, state) {
        if (_editingRow == _remoteRow) {
          return _buildRemoteEditRow();
        }
        final String value = state.status == RemoteLoginStatus.notConfigured
            ? 'remote_not_set'.tr()
            : '${state.account} ${_remoteStatusLabel(state.status)}';
        return _SettingRow(
          highlighted: inContent && c.row == _remoteRow,
          label: 'settings_remote'.tr(),
          value: value,
          canStepLeft: false,
          canStepRight: state.status != RemoteLoginStatus.notConfigured,
          onTap: () {
            c.select(_remoteRow);
            _beginInlineEdit(_remoteRow);
          },
          onStepLeft: () => c.select(_remoteRow),
          onStepRight: () {
            c.select(_remoteRow);
            _beginInlineEdit(_remoteRow);
          },
        );
      },
    );
  }

  /// 「远程」行的登录状态文案。
  String _remoteStatusLabel(RemoteLoginStatus status) {
    switch (status) {
      case RemoteLoginStatus.notConfigured:
        return 'remote_not_set'.tr();
      case RemoteLoginStatus.loggingIn:
        return 'remote_logging_in'.tr();
      case RemoteLoginStatus.loggedIn:
        return 'remote_logged_in'.tr();
      case RemoteLoginStatus.error:
        return 'remote_error'.tr();
    }
  }

  /// 行内输入编辑态的焦点节点，按行号取（未配置的行返回 null）。
  FocusNode? _focusNodeOf(int row) => row == _remoteRow ? _remoteInputFocusNode : null;

  /// 进入行内输入编辑态：各行为自己的输入框装文本，下一帧聚焦弹出输入法。
  void _beginInlineEdit(int row) {
    if (_editingRow != null || !mounted) return;
    if (_focusNodeOf(row) == null) return; // 未配置焦点节点的行不进入编辑态
    // 实时通道账号：预填当前账号。
    _remoteInputController.text = context.read<RemoteLoginBloc>().state.account;
    _editingRow = row;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNodeOf(row)?.requestFocus();
    });
  }

  /// 提交行内输入：按编辑中的行分发；空串一律视为取消。
  Future<void> _submitInlineEdit() async {
    final int? row = _editingRow;
    if (row == null) return;
    if (row == _remoteRow) {
      final String account = _remoteInputController.text.trim();
      _cancelInlineEdit();
      if (account.isEmpty || !mounted) return;
      context.read<RemoteLoginBloc>().add(RemoteLoginSubmit(account));
    } else {
      // 未配置提交分支的行：安全退出编辑态，避免吞键卡死。
      _cancelInlineEdit();
    }
  }

  /// 退出行内输入编辑态（取消，不提交）。
  void _cancelInlineEdit() {
    final int? row = _editingRow;
    if (row == null) return;
    _editingRow = null;
    _focusNodeOf(row)?.unfocus();
    if (mounted) setState(() {});
  }

  /// 编辑态下拦截返回（取消编辑）与 OK/Enter/空格（提交），
  /// 防止冒泡到 MainApp 根键处理器触发退出确认或 activate no-op。
  ///
  /// 仅覆盖经焦点链冒泡的按键（物理/蓝牙遥控器、键盘）。悬浮遥控器不走
  /// 焦点链（FloatingRemote.onKey 直调 `MainApp._handleLogical`），由
  /// [MainApp] 在返回/OK 分支优先检查 [ProfilePage.isInlineEditing] 处理。
  ///
  /// 未编辑态一律 ignored，保持既有焦点导航/激活/退出行为不变；
  /// 上下左右键也保持 ignored（上/下移焦会经 _onFocusChanged 取消编辑，符合设计）。
  ///
  /// 返回与 OK 两类键集合与 `MainApp._handleLogical` 镜像。
  KeyEventResult _handlePageKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final LogicalKeyboardKey key = event.logicalKey;
    // 消息悬浮层可见时优先拦截物理按键（与 MainApp._handleLogical 镜像），
    // 避免与下方远程编辑态的 OK/返回分支抢占焦点输入。
    if (MessageOverlayController.instance.visible) {
      MessageOverlayController.instance.onAnyKey();
      final bool isBack = key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack;
      if (isBack) {
        MessageOverlayController.instance.handleBack();
        return KeyEventResult.handled;
      }
      final bool ok =
          key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.numpadEnter ||
          key == LogicalKeyboardKey.select ||
          key == LogicalKeyboardKey.gameButtonA ||
          key == LogicalKeyboardKey.space;
      if (ok) {
        MessageOverlayController.instance.handleOk();
        return KeyEventResult.handled;
      }
      if (MessageOverlayController.instance.detail) {
        final bool isArrow = key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowDown;
        if (isArrow) {
          MessageOverlay.scrollDetail(key == LogicalKeyboardKey.arrowUp ? -1 : 1);
          return KeyEventResult.handled;
        }
      }
      return KeyEventResult.handled; // 吞掉其余按键
    }
    if (_editingRow == null) return KeyEventResult.ignored;
    // 返回键（部分遥控器发 goBack；悬浮遥控器的 escape 走 MainApp 分支）→ 取消编辑。
    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack) {
      _cancelInlineEdit();
      return KeyEventResult.handled;
    }
    // OK 键 → 提交输入。
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.gameButtonA) {
      unawaited(_submitInlineEdit());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// 「远程」行编辑态：共用 [_InlineEditFrame]；已登录时下方附二维码。
  Widget _buildRemoteEditRow() {
    final RemoteLoginState remoteState = context.read<RemoteLoginBloc>().state;
    return _InlineEditFrame(
      label: 'settings_remote'.tr(),
      controller: _remoteInputController,
      focusNode: _remoteInputFocusNode,
      hintText: 'remote_input_hint'.tr(),
      onCancel: _cancelInlineEdit,
      onSubmit: _submitInlineEdit,
      obscureText: false,
      child: (remoteState.status == RemoteLoginStatus.loggedIn && remoteState.account.isNotEmpty)
          ? QrImageView(data: remoteState.account, size: 120, backgroundColor: Colors.white)
          : null,
    );
  }

  /// 「免责声明」行：只读说明行。
  ///
  /// 声明频道数据来源与使用范围，没有可切换的值，因此不显示左右步进指示；
  /// 文案较长，允许换行（见 [_SettingRow.wrapValue]）。
  Widget _buildDisclaimerRow(bool inContent, ProfileFocusController c) {
    return _SettingRow(
      highlighted: inContent && c.row == _disclaimerRow,
      label: 'disclaimer_title'.tr(),
      value: 'disclaimer_body'.tr(),
      canStepLeft: false,
      canStepRight: false,
      wrapValue: true,
      onTap: () => c.select(_disclaimerRow),
      onStepLeft: () => c.select(_disclaimerRow),
      onStepRight: () => c.select(_disclaimerRow),
    );
  }

  /// 「版本」行：只读说明行，与「天气数据来源」同样只展示不可切换。
  ///
  /// 值来自 [AppVersion]（DI 单例，启动时用 package_info_plus 读取平台打包信息，
  /// 即 pubspec 的 `version:`），因此发版只需改 pubspec、无需改代码。
  Widget _buildVersionRow(bool inContent, ProfileFocusController c) {
    return _SettingRow(
      highlighted: inContent && c.row == _versionRow,
      label: 'settings_version'.tr(),
      value: Injection.get<AppVersion>().display,
      canStepLeft: false,
      canStepRight: false,
      onTap: () => c.select(_versionRow),
      onStepLeft: () => c.select(_versionRow),
      onStepRight: () => c.select(_versionRow),
    );
  }

  /// 「天气数据来源」行：只读说明行。
  ///
  /// 当前仅接入心知天气一家，没有可切换的值，因此左右步进指示不显示、
  /// 左右键也不改变任何内容；它仍可作为普通行被选中（高亮）。
  Widget _buildWeatherSourceRow(bool inContent, ProfileFocusController c) {
    return _SettingRow(
      highlighted: inContent && c.row == _weatherSourceRow,
      label: 'weather_data_source'.tr(),
      value: 'weather_source_seniverse'.tr(),
      canStepLeft: false,
      canStepRight: false,
      onTap: () => c.select(_weatherSourceRow),
      onStepLeft: () => c.select(_weatherSourceRow),
      onStepRight: () => c.select(_weatherSourceRow),
    );
  }
}

/// 单行设置项：左侧选项名 + 中间空白 + 右侧当前值与步进指示（< 值 >）。
///
/// 选中行高亮；触摸/点击可直接移动选择并步进。具体改值由
/// [ProfileFocusController.onStepRow]（即 [ProfilePage]）执行。
/// [wrapValue] 为 true 时值文本允许多行换行（长说明文案用），
/// 否则保持单行右对齐（普通短值）。
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
    this.wrapValue = false,
  });

  final bool highlighted;
  final String label;
  final String value;
  final bool canStepLeft;
  final bool canStepRight;
  final VoidCallback onTap;
  final VoidCallback onStepLeft;
  final VoidCallback onStepRight;
  final bool wrapValue;

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
          color: highlighted ? scheme.primaryContainer.withValues(alpha: 0.30) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: highlighted ? scheme.primary : Colors.transparent, width: 2),
        ),
        child: Row(
          crossAxisAlignment: wrapValue ? CrossAxisAlignment.start : CrossAxisAlignment.center,
          children: <Widget>[
            Text(
              label,
              style: textTheme.titleMedium?.copyWith(color: highlighted ? scheme.onSurface : scheme.onSurfaceVariant),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: wrapValue ? CrossAxisAlignment.start : CrossAxisAlignment.center,
                children: <Widget>[
                  if (canStepLeft) _StepIcon(icon: Icons.chevron_left, color: accent, onTap: onStepLeft),
                  Flexible(
                    child: Text(
                      value,
                      textAlign: wrapValue ? TextAlign.start : TextAlign.right,
                      maxLines: wrapValue ? null : 1,
                      overflow: wrapValue ? null : TextOverflow.ellipsis,
                      style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: accent),
                    ),
                  ),
                  if (canStepRight) _StepIcon(icon: Icons.chevron_right, color: accent, onTap: onStepRight),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 步进指示图标（< 或 >），触摸/点击也可直接步进。
class _StepIcon extends StatelessWidget {
  const _StepIcon({required this.icon, required this.color, required this.onTap});

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

/// 行内输入编辑态的共用外框：标题 + 输入框 + ✕ 取消 + ✓ 提交。
///
/// 实时通道「远程」行等输入行共用；[child] 用于附加内容（如远程行的二维码）。
/// 视觉与原编辑态完全一致（外框、字体、密度逐项照搬）。
class _InlineEditFrame extends StatelessWidget {
  const _InlineEditFrame({
    required this.label,
    required this.controller,
    required this.focusNode,
    required this.hintText,
    required this.onCancel,
    required this.onSubmit,
    this.obscureText = false,
    this.child,
  });

  final String label;
  final TextEditingController controller;
  final FocusNode focusNode;
  final String hintText;
  final VoidCallback onCancel;
  final VoidCallback onSubmit;

  /// 密码类输入用圆点遮蔽（默认 false，与原云信行一致）。
  final bool obscureText;

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme textTheme = Theme.of(context).textTheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.30),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.primary, width: 2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(label, style: textTheme.titleMedium?.copyWith(color: scheme.onSurface)),
              const SizedBox(width: 16),
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  textInputAction: TextInputAction.done,
                  textCapitalization: TextCapitalization.none,
                  autocorrect: false,
                  obscureText: obscureText,
                  style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: scheme.primary),
                  decoration: InputDecoration(hintText: hintText, isDense: true, border: InputBorder.none),
                  onSubmitted: (_) => onSubmit(),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.close, color: scheme.onSurfaceVariant),
                onPressed: onCancel,
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.check, color: scheme.primary),
                onPressed: onSubmit,
              ),
            ],
          ),
          if (child != null) Padding(padding: const EdgeInsets.only(top: 8), child: child),
        ],
      ),
    );
  }
}
