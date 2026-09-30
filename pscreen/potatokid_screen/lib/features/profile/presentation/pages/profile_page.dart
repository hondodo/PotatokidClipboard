import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:potatokid_screen/app/config/app_config.dart';
import 'package:potatokid_screen/core/di/injection.dart';
import 'package:potatokid_screen/core/logging/log_service.dart';
import 'package:potatokid_screen/core/utils/app_settings.dart';
import 'package:potatokid_screen/core/utils/app_version.dart';
import 'package:potatokid_screen/features/app/application/bloc/app_bloc.dart';
import 'package:potatokid_screen/features/app/application/bloc/app_event.dart';
import 'package:potatokid_screen/features/app/application/bloc/app_state.dart';
import 'package:potatokid_screen/features/app/application/video_aspect_mode.dart';
import 'package:potatokid_screen/features/iptv/application/bloc/iptv_bloc.dart';
import 'package:potatokid_screen/features/iptv/application/bloc/iptv_event.dart';
import 'package:potatokid_screen/features/profile/application/profile_focus_controller.dart';
import 'package:potatokid_screen/features/weather/application/bloc/weather_bloc.dart';
import 'package:potatokid_screen/features/weather/application/bloc/weather_event.dart';
import 'package:potatokid_screen/shared/widgets/confirm_dialog.dart';
import 'package:restart_app/restart_app.dart';

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
  /// 「刷新频道」行在 [ProfileFocusController.row] 中的序号。
  static const int _refreshRow = 6;

  /// 「清理失效源」行在 [ProfileFocusController.row] 中的序号。
  static const int _removeInvalidRow = 7;

  /// 「代理重试」行在 [ProfileFocusController.row] 中的序号。
  static const int _proxyRetryRow = 8;

  /// 「重置」行（清空全部持久化缓存并重启应用）的序号。
  static const int _resetRow = 9;

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
  static List<String> get _weatherCityOptions =>
      <String>['', ...AppConfig.weatherCities];

  /// 天气城市选项的展示文案：空串为「自动」，其余直接显示城市名。
  static String _weatherCityLabel(String city) =>
      city.isEmpty ? 'weather_city_auto'.tr() : city;

  /// 刷新状态文案：null=空闲，非空=「刷新中…」/「已刷新」/「刷新失败」。
  final ValueNotifier<String?> _refreshMsg = ValueNotifier<String?>(null);
  bool _refreshing = false;

  /// 重置流程是否正在进行（含确认弹窗），避免重复触发/叠出多个弹窗。
  bool _resetting = false;

  Timer? _cityApplyTimer;

  /// 各设置行的 GlobalKey：用于「选中行滚动入屏」。
  final List<GlobalKey> _rowKeys = List<GlobalKey>.generate(
    ProfileFocusController.rowCount,
    (_) => GlobalKey<State>(),
  );

  int _prevRow = 0;
  bool _prevFocused = false;

  @override
  void initState() {
    super.initState();
    ProfileFocusController.instance.onStepRow = _stepRow;
    ProfileFocusController.instance.onActivateRow = _onActivateRow;
    ProfileFocusController.instance.addListener(_onFocusChanged);
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
    _cityApplyTimer?.cancel();
    _refreshMsg.dispose();
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
    if (!c.focused) return;
    if (c.row == _prevRow && _prevFocused) return;
    _prevRow = c.row;
    _prevFocused = c.focused;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final BuildContext? ctx = _rowKeys[c.row].currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.5,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  /// OK/触摸激活当前行：刷新频道行与重置行有动作。
  void _onActivateRow(int row) {
    if (row == _refreshRow && mounted) _refreshChannels();
    if (row == _resetRow && mounted) _resetAll();
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
      final RestartResult result = await Restart.restartApp(
        mode: RestartMode.process,
        forceKill: true,
      );
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

  /// 按当前行执行真正的值改动（主题/语言/悬浮遥控器/硬解/画面/天气城市/刷新频道/清理失效源）。
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
      case 5: // 天气城市：自动 → .env 配置的城市 步进（5 秒后生效）
        final List<String> opts = _weatherCityOptions;
        final int cur = opts.indexOf(context.read<AppBloc>().state.weatherCity);
        final int val = cur < 0 ? 0 : cur;
        final int next = (val + delta).clamp(0, opts.length - 1);
        context.read<AppBloc>().add(ChangeWeatherCity(opts[next]));
        _scheduleCityApply();
        break;
      case 6: // 刷新频道（左/右键按下同样触发）
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
              KeyedSubtree(key: _rowKeys[6], child: _buildRefreshRow(inContent, c)),
              const SizedBox(height: 12),
              KeyedSubtree(
                key: _rowKeys[_removeInvalidRow],
                child: _buildRemoveInvalidRow(inContent, c),
              ),
              const SizedBox(height: 12),
              KeyedSubtree(
                key: _rowKeys[_proxyRetryRow],
                child: _buildProxyRetryRow(inContent, c),
              ),
              const SizedBox(height: 12),
              KeyedSubtree(
                key: _rowKeys[_resetRow],
                child: _buildResetRow(inContent, c),
              ),
              const SizedBox(height: 12),
              KeyedSubtree(
                key: _rowKeys[_versionRow],
                child: _buildVersionRow(inContent, c),
              ),
              const SizedBox(height: 12),
              KeyedSubtree(
                key: _rowKeys[_weatherSourceRow],
                child: _buildWeatherSourceRow(inContent, c),
              ),
              const SizedBox(height: 12),
              KeyedSubtree(
                key: _rowKeys[_disclaimerRow],
                child: _buildDisclaimerRow(inContent, c),
              ),
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
          crossAxisAlignment: wrapValue
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.center,
          children: <Widget>[
            Text(
              label,
              style: textTheme.titleMedium?.copyWith(
                color: highlighted ? scheme.onSurface : scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: wrapValue
                    ? CrossAxisAlignment.start
                    : CrossAxisAlignment.center,
                children: <Widget>[
                  if (canStepLeft)
                    _StepIcon(
                      icon: Icons.chevron_left,
                      color: accent,
                      onTap: onStepLeft,
                    ),
                  Flexible(
                    child: Text(
                      value,
                      textAlign: wrapValue ? TextAlign.start : TextAlign.right,
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: accent,
                      ),
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
