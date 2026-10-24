import 'dart:async';

import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_reorderable_grid_view/widgets/reorderable_builder.dart';
import 'package:pscreen_home/app/config/ha_config.dart';
import 'package:pscreen_home/core/di/injection.dart';
import 'package:pscreen_home/core/network/ha_ws_client.dart';
import 'package:pscreen_home/core/router/app_router.dart';
import 'package:pscreen_home/core/router/route_names.dart';
import 'package:pscreen_home/features/connection/application/bloc/connection_bloc.dart';
import 'package:pscreen_home/features/connection/application/bloc/connection_event.dart';
import 'package:pscreen_home/features/connection/application/bloc/connection_state.dart';
import 'package:pscreen_home/features/home/application/bloc/home_bloc.dart';
import 'package:pscreen_home/features/home/application/bloc/home_event.dart';
import 'package:pscreen_home/features/home/application/bloc/home_state.dart';
import 'package:pscreen_home/features/home/application/history_service.dart';
import 'package:pscreen_home/features/home/application/metric_history.dart';
import 'package:pscreen_home/features/screen/application/clock_formatter.dart';
import 'package:pscreen_home/features/home/domain/models/ha_device_group.dart';
import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';
import 'package:pscreen_home/features/home/domain/models/ha_registry_model.dart';
import 'package:pscreen_home/features/home/domain/models/home_climate_summary.dart';
import 'package:pscreen_home/features/home/domain/models/metric.dart';
import 'package:pscreen_home/features/home/domain/models/metric_source.dart';
import 'package:pscreen_home/features/home/domain/models/air_fryer_summary.dart';
import 'package:pscreen_home/features/home/domain/models/fan_summary.dart';
import 'package:pscreen_home/features/home/domain/models/fridge_summary.dart';
import 'package:pscreen_home/features/home/domain/models/kettle_summary.dart';
import 'package:pscreen_home/features/home/domain/models/lock_summary.dart';
import 'package:pscreen_home/features/home/domain/models/projector_summary.dart';
import 'package:pscreen_home/features/home/domain/models/rice_cooker_summary.dart';
import 'package:pscreen_home/features/home/domain/models/range_hood_summary.dart';
import 'package:pscreen_home/features/home/domain/models/water_purifier_summary.dart';
import 'package:pscreen_home/features/home/domain/models/multi_switch_summary.dart';
import 'package:pscreen_home/features/home/domain/models/socket_summary.dart';
import 'package:pscreen_home/features/home/domain/models/washer_summary.dart';
import 'package:pscreen_home/features/home/domain/models/water_heater_summary.dart';
import 'package:pscreen_home/features/home/presentation/components/button_widget.dart';
import 'package:pscreen_home/features/home/presentation/components/climate_display.dart';
import 'package:pscreen_home/features/home/presentation/components/climate_widget.dart';
import 'package:pscreen_home/features/home/presentation/components/device_widget.dart';
import 'package:pscreen_home/features/home/presentation/components/fan_widget.dart';
import 'package:pscreen_home/features/home/presentation/components/fan_light_widget.dart';
import 'package:pscreen_home/features/home/presentation/components/air_fryer_widget.dart';
import 'package:pscreen_home/features/home/presentation/components/fridge_widget.dart';
import 'package:pscreen_home/features/home/presentation/components/kettle_widget.dart';
import 'package:pscreen_home/features/home/presentation/components/light_widget.dart';
import 'package:pscreen_home/features/home/presentation/components/lock_widget.dart';
import 'package:pscreen_home/features/home/presentation/components/projector_widget.dart';
import 'package:pscreen_home/features/home/presentation/components/rice_cooker_widget.dart';
import 'package:pscreen_home/features/home/presentation/components/range_hood_widget.dart';
import 'package:pscreen_home/features/home/presentation/components/multi_switch_widget.dart';
import 'package:pscreen_home/features/home/presentation/components/socket_widget.dart';
import 'package:pscreen_home/features/home/presentation/components/value_widget.dart';
import 'package:pscreen_home/features/home/presentation/components/washer_widget.dart';
import 'package:pscreen_home/features/home/presentation/components/water_heater_widget.dart';
import 'package:pscreen_home/features/home/presentation/components/water_purifier_widget.dart';
import 'package:pscreen_screen/features/weather/application/bloc/weather_bloc.dart';
import 'package:pscreen_screen/features/weather/application/bloc/weather_state.dart';
import 'package:pscreen_screen/features/weather/data/weather_data_convert.dart';
import 'package:pscreen_screen/features/weather/domain/models/weather_models.dart';

/// 主页面：中控台。
///
/// 布局（对应原构想注释）：
/// - 顶部第一行：**家庭**标签（✅ 区域名前缀解析：薯仔4号的家 / 金科1204 / 棠德304）
/// - 第二行：**房间**标签（✅ 基于 area 注册表，受家庭筛选，后缀为可控实体数）
/// - 下方网格：按 家庭 ▸ 房间 两级过滤，卡片标注实体所属房间
/// - 待实现：常用设备横向列表（M3，设置页勾选常用实体）
class HomeControllBoard extends StatefulWidget {
  const HomeControllBoard({super.key});

  @override
  State<HomeControllBoard> createState() => _HomeControllBoardState();
}

class _HomeControllBoardState extends State<HomeControllBoard> {
  @override
  void initState() {
    super.initState();
    // 连接可能在页面挂载前就已就绪（例如从其他页面返回 / 热重启），
    // BlocListener 只监听后续状态变化，这里补一次初始检查。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ConnectionState connection = context.read<ConnectionBloc>().state;
      final HomeState home = context.read<HomeBloc>().state;
      if (connection.isReady && !home.hasLoaded && !home.isLoading) {
        context.read<HomeBloc>().add(const LoadHome());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: <BlocListener<dynamic, dynamic>>[
        // 连接就绪（含重连成功）时加载数据
        BlocListener<ConnectionBloc, ConnectionState>(
          listenWhen: (ConnectionState prev, ConnectionState cur) =>
              !prev.isReady && cur.isReady,
          listener: (BuildContext context, ConnectionState state) =>
              context.read<HomeBloc>().add(const LoadHome()),
        ),
        // 控制失败提示；空数据时的加载错误保留在页面上，供重试。
        BlocListener<HomeBloc, HomeState>(
          listenWhen: (HomeState prev, HomeState cur) =>
              cur.errorMessage != null && cur.errorMessage != prev.errorMessage,
          listener: (BuildContext context, HomeState state) {
            if (state.entities.isNotEmpty) {
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(
                    content: Text(state.errorMessage ?? ''),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              context.read<HomeBloc>().add(const ClearHomeError());
            }
          },
        ),
      ],
      child: Scaffold(
        appBar: AppBar(
          // 标题含两行（时钟 + 日期），比默认单行 toolbar 略高。
          toolbarHeight: 64,
          title: const _HomeTitle(),
          actions: <Widget>[
            const _ConnectionStatus(),
            IconButton(
              tooltip: '刷新',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () => context.read<HomeBloc>().add(const LoadHome()),
            ),
            IconButton(
              tooltip: '时钟',
              icon: const Icon(Icons.schedule_rounded),
              onPressed: () =>
                  Injection.get<AppRouter>().push(RouteNames.clockPath),
            ),
            IconButton(
              tooltip: '直播',
              icon: const Icon(Icons.live_tv_rounded),
              onPressed: () =>
                  Injection.get<AppRouter>().push(RouteNames.livePath),
            ),
            IconButton(
              tooltip: '天气',
              icon: const Icon(Icons.cloud_outlined),
              onPressed: () =>
                  Injection.get<AppRouter>().push(RouteNames.weatherPath),
            ),
            IconButton(
              tooltip: '遥控',
              icon: const Icon(Icons.cast_rounded),
              onPressed: () =>
                  Injection.get<AppRouter>().push(RouteNames.remoteControlPath),
            ),
            IconButton(
              tooltip: '设置',
              icon: const Icon(Icons.settings_rounded),
              onPressed: () =>
                  Injection.get<AppRouter>().push(RouteNames.settingsPath),
            ),
          ],
        ),
        body: const _Body(),
      ),
    );
  }
}

/// AppBar 标题：时钟（数字等宽）+ 日期 / 农历 / 星期 + 当前天气。
///
/// 天气取自全局 [WeatherBloc]，与天气页共享同一份数据；自动刷新由该状态机
/// 内置的 5 分钟定时器驱动。时间每秒刷新。
class _HomeTitle extends StatefulWidget {
  const _HomeTitle();

  @override
  State<_HomeTitle> createState() => _HomeTitleState();
}

class _HomeTitleState extends State<_HomeTitle> {
  DateTime _now = DateTime.now();
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted) return;
      final DateTime now = DateTime.now();
      // 200ms 轮询、秒数变化才 setState：避免 1s 周期计时器漂移
      // 导致显示 18 后直接跳到 20，同时不会增加每秒重建次数。
      if (now.second == _now.second) return;
      setState(() => _now = now);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        const _PinnedHomeBadge(),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              formatClockTime(_now),
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
                height: 1.05,
                // 数字等宽：秒数跳动时标题宽度不抖动。
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
            Text(
              formatDate(_now),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.2,
              ),
            ),
          ],
        ),
        const SizedBox(width: 8),
        Column(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Text(
              formatLunarLine(_now),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.2,
              ),
            ),
            Text(
              formatWeekLine(_now),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.2,
              ),
            ),
          ],
        ),
        const SizedBox(width: 16),
        const _NowWeather(),
      ],
    );
  }
}

/// 顶部左上角的固定家庭摘要（仅 `.env` 指定家庭时显示）。
///
/// 指定家庭后主页会隐藏家庭概览条，这里用紧凑样式补回家名与温湿度：
/// 家庭图标 + [家庭名 | 温度 湿度]，温湿度前带图标；两行布局适配 AppBar 高度。
class _PinnedHomeBadge extends StatelessWidget {
  const _PinnedHomeBadge();

  static const Color _accent = Color(0xFF5FD3C4);

  @override
  Widget build(BuildContext context) {
    final String pinnedHome = HaConfig.pinnedHomeName;
    if (pinnedHome.isEmpty) return const SizedBox.shrink();

    return BlocBuilder<HomeBloc, HomeState>(
      builder: (BuildContext context, HomeState state) {
        if (!state.availableHomes.contains(pinnedHome)) {
          return const SizedBox.shrink();
        }
        final List<HomeClimateSummary> summaries = state.homeClimateSummaries;
        if (summaries.isEmpty) return const SizedBox.shrink();
        final HomeClimateSummary summary = summaries.firstWhere(
          (HomeClimateSummary item) => item.homeName == pinnedHome,
          orElse: () => summaries.first,
        );

        final ThemeData theme = Theme.of(context);
        return Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.home_rounded, size: 24, color: _accent),
              const SizedBox(width: 8),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    summary.homeName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                    ),
                  ),
                  if (summary.hasData) ...<Widget>[
                    const SizedBox(height: 2),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        if (summary.temperature != null) ...<Widget>[
                          const Icon(
                            Icons.thermostat_rounded,
                            size: 15,
                            color: _accent,
                          ),
                          Text(
                            '${formatTemperature(summary.temperature)}°',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: _accent,
                              height: 1.1,
                            ),
                          ),
                        ],
                        if (summary.temperature != null &&
                            summary.humidity != null)
                          const SizedBox(width: 8),
                        if (summary.humidity != null) ...<Widget>[
                          Icon(
                            Icons.water_drop_rounded,
                            size: 13,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          Text(
                            '${summary.humidity}%',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              height: 1.1,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 当前天气：图标 + 气温，无数据时静默隐藏。
class _NowWeather extends StatelessWidget {
  const _NowWeather();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WeatherBloc, WeatherState>(
      builder: (BuildContext context, WeatherState state) {
        final WeatherNow? now = state.data?.now;
        final ThemeData theme = Theme.of(context);
        if (now == null) return const SizedBox.shrink();
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            WeatherDataConvert.weatherIcon(context, now.skycon, size: 28),
            const SizedBox(width: 8),
            Column(
              children: [
                Text(
                  '${now.temperature?.round() ?? '--'}°',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  now.city,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// AppBar 右侧的连接状态：状态点 + 文案，失败时提供重试按钮。
class _ConnectionStatus extends StatelessWidget {
  const _ConnectionStatus();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ConnectionBloc, ConnectionState>(
      builder: (BuildContext context, ConnectionState state) {
        final (String label, Color color) = switch (state.phase) {
          HaConnectionPhase.ready => ('已连接', Colors.greenAccent),
          HaConnectionPhase.connecting => ('连接中', Colors.orangeAccent),
          HaConnectionPhase.authenticating => ('认证中', Colors.orangeAccent),
          HaConnectionPhase.authFailed => (
            state.message ?? '认证失败',
            Colors.redAccent,
          ),
          HaConnectionPhase.disconnected => (
            state.isRetrying ? '重连中…' : '未连接',
            Colors.redAccent,
          ),
        };
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
            if (state.canRetry)
              IconButton(
                tooltip: '重试',
                icon: const Icon(Icons.refresh_rounded),
                onPressed: () =>
                    context.read<ConnectionBloc>().add(const RetryConnection()),
              ),
          ],
        );
      },
    );
  }
}

/// 主体：未连接时显示连接占位，连接后显示房间标签行 + 快捷控件网格。
class _Body extends StatelessWidget {
  const _Body();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ConnectionBloc, ConnectionState>(
      builder: (BuildContext context, ConnectionState conn) {
        if (!conn.isReady) return _ConnectionPlaceholder(state: conn);
        return const Column(
          children: <Widget>[
            _HomeOverviewBar(),
            _AreaBar(),
            Expanded(child: _ControlGrid()),
          ],
        );
      },
    );
  }
}

/// 家庭概览条：家庭名 + 温度 / 湿度。
///
/// - 未选家庭：横向列出全部家庭，每张卡显示该家庭的温湿度；
/// - 已选家庭：只显示所选家庭的摘要，并提供「全部」返回；
/// - `.env` 的 [HaConfig.pinnedHomeName] 指定了家庭时整条隐藏：
///   此时主页已固定只显示该家庭，无需再提供家庭切换入口。
///
/// 温湿度来自家庭内 climate 实体的 current_temperature / current_humidity，
/// 缺失的项直接不渲染（不显示占位符）。
class _HomeOverviewBar extends StatelessWidget {
  const _HomeOverviewBar();

  static const Color _accent = Color(0xFF5FD3C4);

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<HomeBloc, HomeState>(
      builder: (BuildContext context, HomeState state) {
        // .env 指定了固定家庭：主页只展示该家庭，概览条里的家庭名 /
        // 「全部」按钮不再有意义，直接隐藏，给设备网格腾出空间。
        final String pinnedHome = HaConfig.pinnedHomeName;
        if (pinnedHome.isNotEmpty &&
            state.availableHomes.contains(pinnedHome)) {
          return const SizedBox.shrink();
        }

        final List<HomeClimateSummary> summaries = state.homeClimateSummaries;
        if (summaries.isEmpty) return const SizedBox.shrink();

        final String selected = state.effectiveHomeName;
        if (selected.isNotEmpty) {
          final HomeClimateSummary summary = summaries.firstWhere(
            (HomeClimateSummary item) => item.homeName == selected,
            orElse: () => summaries.first,
          );
          return SizedBox(
            height: 84,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: _SelectedHomeSummary(
                summary: summary,
                onShowAll: () =>
                    context.read<HomeBloc>().add(const HomeSelected('')),
              ),
            ),
          );
        }

        return SizedBox(
          height: 84,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            itemCount: summaries.length,
            separatorBuilder: (BuildContext context, int index) =>
                const SizedBox(width: 8),
            itemBuilder: (BuildContext context, int index) {
              final HomeClimateSummary summary = summaries[index];
              return _HomeSummaryCard(
                summary: summary,
                onTap: () => context.read<HomeBloc>().add(
                  HomeSelected(summary.homeName),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

/// 未选家庭时的家庭温湿度卡（点击选中该家庭）。
class _HomeSummaryCard extends StatelessWidget {
  const _HomeSummaryCard({required this.summary, required this.onTap});

  final HomeClimateSummary summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return SizedBox(
      width: 190,
      height: 68,
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(
                      Icons.home_rounded,
                      size: 15,
                      color: theme.colorScheme.outline,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        summary.homeName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                if (summary.hasData) ...<Widget>[
                  const SizedBox(height: 4),
                  _ClimateValues(summary: summary),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 已选家庭的摘要（更宽，右侧「全部」返回）。
class _SelectedHomeSummary extends StatelessWidget {
  const _SelectedHomeSummary({required this.summary, required this.onShowAll});

  final HomeClimateSummary summary;
  final VoidCallback onShowAll;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.home_rounded,
            size: 20,
            color: _HomeOverviewBar._accent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  summary.homeName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (summary.hasData) ...<Widget>[
                  const SizedBox(height: 2),
                  _ClimateValues(summary: summary),
                ],
              ],
            ),
          ),
          TextButton(
            onPressed: onShowAll,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            child: const Text('全部'),
          ),
        ],
      ),
    );
  }
}

/// 温度 / 湿度数值行（任一项缺失就不渲染该项，来源设备通过长按提示）。
class _ClimateValues extends StatelessWidget {
  const _ClimateValues({required this.summary});

  final HomeClimateSummary summary;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Widget values = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        if (summary.temperature != null)
          Text(
            '${formatTemperature(summary.temperature)}°C',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: _HomeOverviewBar._accent,
            ),
          ),
        if (summary.temperature != null && summary.humidity != null)
          const SizedBox(width: 8),
        if (summary.humidity != null)
          Text(
            '${summary.humidity}%',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
    final String? source = summary.sourceName;
    if (source == null) return values;
    return Tooltip(message: '数据来源：$source', child: values);
  }
}

/// 第二行：房间标签（原构想的「地区名称」行），受家庭标签筛选。
/// 仅展示含可控实体的房间，标签后缀为该房间的可控实体数量。
class _AreaBar extends StatelessWidget {
  const _AreaBar();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<HomeBloc, HomeState>(
      builder: (BuildContext context, HomeState state) {
        final List<HaArea> areas = state.visibleAreas;
        if (areas.isEmpty) return const SizedBox.shrink();
        final String current = state.effectiveAreaId;
        final bool scopedByHome = state.effectiveHomeName.isNotEmpty;
        return SizedBox(
          height: 52,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            itemCount: areas.length + 1,
            separatorBuilder: (BuildContext context, int index) =>
                const SizedBox(width: 8),
            itemBuilder: (BuildContext context, int index) {
              if (index == 0) {
                return ChoiceChip(
                  label: const Text('全部'),
                  selected: current.isEmpty,
                  onSelected: (_) =>
                      context.read<HomeBloc>().add(const AreaSelected('')),
                );
              }
              final HaArea area = areas[index - 1];
              // 已选家庭时房间名天然不重复，用短名；否则用完整区域名区分
              final String label = scopedByHome ? area.roomName : area.name;
              return ChoiceChip(
                label: Text('$label ${state.areaCount(area.areaId)}'),
                selected: current == area.areaId,
                onSelected: (_) =>
                    context.read<HomeBloc>().add(AreaSelected(area.areaId)),
              );
            },
          ),
        );
      },
    );
  }
}

/// 连接占位视图：连接中转圈，失败给出原因与重试入口。
class _ConnectionPlaceholder extends StatelessWidget {
  const _ConnectionPlaceholder({required this.state});

  final ConnectionState state;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool connecting =
        state.phase == HaConnectionPhase.connecting ||
        state.phase == HaConnectionPhase.authenticating;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (connecting) ...<Widget>[
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text('正在连接 Home Assistant…', style: theme.textTheme.bodyMedium),
            ] else ...<Widget>[
              Icon(
                state.phase == HaConnectionPhase.authFailed
                    ? Icons.lock_rounded
                    : Icons.cloud_off_rounded,
                size: 48,
                color: theme.colorScheme.outline,
              ),
              const SizedBox(height: 16),
              Text(
                state.message ??
                    (state.isRetrying ? '连接中断，正在自动重试…' : '未连接到 Home Assistant'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              if (state.canRetry) ...<Widget>[
                const SizedBox(height: 16),
                FilledButton.tonal(
                  onPressed: () => context.read<ConnectionBloc>().add(
                    const RetryConnection(),
                  ),
                  child: const Text('立即重试'),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// 快捷控件网格：按设备分组，同设备多实体合并为一张卡。
///
/// - 单实体设备：保持原卡片样式，点击即开关（灯在前、开关在后）；
/// - 多实体设备：[DeviceWidget] 合并卡，外层展示设备名 + 聚合状态 +
///   电源键（切主实体），点击卡片其余区域进入设备详情页逐实体控制。
class _ControlGrid extends StatefulWidget {
  const _ControlGrid();

  @override
  State<_ControlGrid> createState() => _ControlGridState();
}

class _ControlGridState extends State<_ControlGrid> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// 手动重试：连接看似在线但请求超时时，先强制重建 WebSocket；
  /// 重建成功后由页面监听自动 LoadHome。非 ready 状态按连接页逻辑重试。
  void _retryLoad(BuildContext context) {
    final ConnectionState connection = context.read<ConnectionBloc>().state;
    if (connection.isReady) {
      context.read<ConnectionBloc>().add(const Reconnect());
    } else if (connection.canRetry) {
      context.read<ConnectionBloc>().add(const RetryConnection());
    } else {
      context.read<HomeBloc>().add(const LoadHome());
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<HomeBloc, HomeState>(
      builder: (BuildContext context, HomeState state) {
        if (state.isLoading && state.entities.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('正在加载设备…'),
              ],
            ),
          );
        }

        // 首次加载失败：保留错误页，等待自动重试或用户手动重连。
        if (state.entities.isEmpty && state.errorMessage != null) {
          return _HomeLoadError(
            message: state.errorMessage!,
            onRetry: () => _retryLoad(context),
          );
        }

        // 还没成功加载过：不要提前显示「没有找到实体」。
        if (!state.hasLoaded && state.entities.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('正在加载设备…'),
              ],
            ),
          );
        }

        final List<HaDeviceGroup> groups = state.deviceGroups;
        if (groups.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.lightbulb_outline_rounded,
                  size: 48,
                  color: Colors.grey,
                ),
                SizedBox(height: 16),
                Text('没有找到实体'),
              ],
            ),
          );
        }

        final Map<String, LockSummary> locks = state.lockSummaries;
        final Map<String, WasherSummary> washers = state.washerSummaries;
        final Map<String, WaterHeaterSummary> waterHeaters =
            state.waterHeaterSummaries;
        final Map<String, KettleSummary> kettles = state.kettleSummaries;
        final Map<String, FanSummary> fans = state.fanSummaries;
        final Map<String, ProjectorSummary> projectors =
            state.projectorSummaries;
        final Map<String, FridgeSummary> fridges = state.fridgeSummaries;
        final Map<String, SocketSummary> sockets = state.socketSummaries;
        final Map<String, MultiSwitchSummary> multiSwitches =
            state.multiSwitchSummaries;
        final Map<String, RiceCookerSummary> riceCookers =
            state.riceCookerSummaries;
        final Map<String, AirFryerSummary> airFryers = state.airFryerSummaries;
        final Map<String, WaterPurifierSummary> purifiers =
            state.waterPurifierSummaries;
        final Map<String, RangeHoodSummary> hoods = state.rangeHoodSummaries;
        final MetricHistoryStore historyStore =
            Injection.get<MetricHistoryStore>();

        Widget buildCard(BuildContext context, int index) {
          final HaDeviceGroup group = groups[index];
          final String areaLabel = state.areaLabelFor(
            group.primary?.entityId ?? group.entities.first.entityId,
          );

          // 门锁：上锁状态 + 电池电量 + 电量更新时间（无快捷开关按钮）
          final LockSummary? lock = group.deviceId == null
              ? null
              : locks[group.deviceId];
          if (lock != null) {
            return LockWidget(
              summary: lock,
              areaLabel: areaLabel,
              showAreaInTitle: state.selectedAreaId.isEmpty,
              onOpenDetail: () => Injection.get<AppRouter>().push(
                RouteNames.deviceDetailPath(group.deviceId!),
              ),
            );
          }

          // 双开开关：两路按键状态
          final MultiSwitchSummary? multiSwitch = group.deviceId == null
              ? null
              : multiSwitches[group.deviceId];
          if (multiSwitch != null) {
            return MultiSwitchWidget(
              summary: multiSwitch,
              areaLabel: areaLabel,
              showAreaInTitle: state.selectedAreaId.isEmpty,
              togglingIds: state.togglingIds,
              onToggleGang: (String entityId) => context.read<HomeBloc>().add(
                ToggleEntity(entityId: entityId),
              ),
              onOpenDetail: () => Injection.get<AppRouter>().push(
                RouteNames.deviceDetailPath(group.deviceId!),
              ),
            );
          }

          // 智能插座：开关 + 当前功率 + 累计电量
          final SocketSummary? socket = group.deviceId == null
              ? null
              : sockets[group.deviceId];
          if (socket != null) {
            final String? powerEntityId =
                socket.stats.acPowerEntityId ?? socket.stats.currentEntityId;
            return SocketWidget(
              summary: socket,
              areaLabel: areaLabel,
              showAreaInTitle: state.selectedAreaId.isEmpty,
              isToggling: state.togglingIds.contains(socket.powerEntityId),
              history: historyStore.watch(socket.deviceId, Metric.power),
              historyService: Injection.get<HistoryService>(),
              deviceId: socket.deviceId,
              powerSource: powerEntityId == null
                  ? null
                  : MetricSource(powerEntityId),
              onToggle: () => context.read<HomeBloc>().add(
                ToggleEntity(entityId: socket.powerEntityId),
              ),
              onOpenDetail: () => Injection.get<AppRouter>().push(
                RouteNames.deviceDetailPath(group.deviceId!),
              ),
            );
          }

          // 油烟机：电源 / 风量 / 灯光 / 延时
          final RangeHoodSummary? hood = group.deviceId == null
              ? null
              : hoods[group.deviceId];
          if (hood != null) {
            return RangeHoodWidget(
              summary: hood,
              areaLabel: areaLabel,
              showAreaInTitle: state.selectedAreaId.isEmpty,
              isToggling: state.togglingIds.contains(hood.powerEntityId),
              onToggle: hood.powerEntityId == null
                  ? () {}
                  : () => context.read<HomeBloc>().add(
                      ToggleEntity(entityId: hood.powerEntityId!),
                    ),
              onOpenDetail: () => Injection.get<AppRouter>().push(
                RouteNames.deviceDetailPath(group.deviceId!),
              ),
            );
          }

          // 净水器：TDS / 水温 / 滤芯
          final WaterPurifierSummary? purifier = group.deviceId == null
              ? null
              : purifiers[group.deviceId];
          if (purifier != null) {
            return WaterPurifierWidget(
              summary: purifier,
              areaLabel: areaLabel,
              showAreaInTitle: state.selectedAreaId.isEmpty,
              onOpenDetail: () => Injection.get<AppRouter>().push(
                RouteNames.deviceDetailPath(group.deviceId!),
              ),
            );
          }

          // 电饭煲：状态 / 剩余时长 + 开始/停止
          final RiceCookerSummary? riceCooker = group.deviceId == null
              ? null
              : riceCookers[group.deviceId];
          if (riceCooker != null) {
            return RiceCookerWidget(
              summary: riceCooker,
              areaLabel: areaLabel,
              showAreaInTitle: state.selectedAreaId.isEmpty,
              onStart: riceCooker.startEntityId == null
                  ? null
                  : () => context.read<HomeBloc>().add(
                      PressNotifyAction(
                        entityId: riceCooker.startEntityId!,
                        message: riceCooker.startMessage,
                      ),
                    ),
              onStop: riceCooker.stopEntityId == null
                  ? null
                  : () => context.read<HomeBloc>().add(
                      PressEntityButton(entityId: riceCooker.stopEntityId!),
                    ),
              onOpenDetail: () => Injection.get<AppRouter>().push(
                RouteNames.deviceDetailPath(group.deviceId!),
              ),
            );
          }

          // 空气炸锅：模式 / 温度 / 时间 + 开始/停止
          final AirFryerSummary? airFryer = group.deviceId == null
              ? null
              : airFryers[group.deviceId];
          if (airFryer != null) {
            return AirFryerWidget(
              summary: airFryer,
              areaLabel: areaLabel,
              showAreaInTitle: state.selectedAreaId.isEmpty,
              onStart: airFryer.startEntityId == null
                  ? null
                  : () => context.read<HomeBloc>().add(
                      PressEntityButton(entityId: airFryer.startEntityId!),
                    ),
              onStop: airFryer.stopEntityId == null
                  ? null
                  : () => context.read<HomeBloc>().add(
                      PressEntityButton(entityId: airFryer.stopEntityId!),
                    ),
              onOpenDetail: () => Injection.get<AppRouter>().push(
                RouteNames.deviceDetailPath(group.deviceId!),
              ),
            );
          }

          // 冰箱：三舱温度 + 模式
          final FridgeSummary? fridge = group.deviceId == null
              ? null
              : fridges[group.deviceId];
          if (fridge != null) {
            return FridgeWidget(
              summary: fridge,
              areaLabel: areaLabel,
              showAreaInTitle: state.selectedAreaId.isEmpty,
              onOpenDetail: () => Injection.get<AppRouter>().push(
                RouteNames.deviceDetailPath(group.deviceId!),
              ),
            );
          }

          // 风扇：模式 / 档位 / 摆风 + 电源
          final FanSummary? fan = group.deviceId == null
              ? null
              : fans[group.deviceId];
          if (fan != null && group.primary?.isFan == true) {
            return FanWidget(
              summary: fan,
              areaLabel: areaLabel,
              showAreaInTitle: state.selectedAreaId.isEmpty,
              isToggling: state.togglingIds.contains(fan.entity.entityId),
              onToggle: () => context.read<HomeBloc>().add(
                ToggleEntity(entityId: fan.entity.entityId),
              ),
              onOpenDetail: () => Injection.get<AppRouter>().push(
                RouteNames.deviceDetailPath(group.deviceId!),
              ),
            );
          }

          // 风扇灯组合：同一设备同时有灯 + 风扇
          final HaEntityStateModel? comboPrimary = group.primary;
          if (fan != null && comboPrimary != null && comboPrimary.isLight) {
            final String toggleId =
                fan.masterSwitchEntityId ?? comboPrimary.entityId;
            return FanLightWidget(
              light: comboPrimary,
              fan: fan,
              areaLabel: areaLabel,
              showAreaInTitle: state.selectedAreaId.isEmpty,
              isToggling: state.togglingIds.contains(toggleId),
              onToggleMaster: () => context.read<HomeBloc>().add(
                ToggleEntity(entityId: toggleId),
              ),
              onOpenDetail: () => Injection.get<AppRouter>().push(
                RouteNames.deviceDetailPath(group.deviceId!),
              ),
            );
          }

          // 投影仪：开关机 / 当前应用 / 音量和亮度
          final ProjectorSummary? projector = group.deviceId == null
              ? null
              : projectors[group.deviceId];
          if (projector != null) {
            final String? powerId = projector.isOn
                ? projector.powerOffEntityId
                : projector.powerOnEntityId;
            final bool powerAvailable = projector.isOn
                ? projector.powerOffAvailable
                : projector.powerOnAvailable;
            return ProjectorWidget(
              summary: projector,
              areaLabel: areaLabel,
              showAreaInTitle: state.selectedAreaId.isEmpty,
              isBusy: powerId != null && state.togglingIds.contains(powerId),
              onPower: powerId == null || !powerAvailable
                  ? () {}
                  : () => context.read<HomeBloc>().add(
                      PressEntityButton(entityId: powerId),
                    ),
              onOpenDetail: () => Injection.get<AppRouter>().push(
                RouteNames.deviceDetailPath(group.deviceId!),
              ),
            );
          }

          // 电热水瓶：当前水温 + 状态 + 模式 + 开始/停止
          final KettleSummary? kettle = group.deviceId == null
              ? null
              : kettles[group.deviceId];
          if (kettle != null) {
            return KettleWidget(
              summary: kettle,
              areaLabel: areaLabel,
              showAreaInTitle: state.selectedAreaId.isEmpty,
              onStart: kettle.startEntityId == null
                  ? null
                  : () => context.read<HomeBloc>().add(
                      PressNotifyAction(
                        entityId: kettle.startEntityId!,
                        message: kettle.startMessage,
                      ),
                    ),
              onStop: kettle.stopEntityId == null
                  ? null
                  : () => context.read<HomeBloc>().add(
                      PressEntityButton(entityId: kettle.stopEntityId!),
                    ),
              onOpenDetail: () => Injection.get<AppRouter>().push(
                RouteNames.deviceDetailPath(group.deviceId!),
              ),
            );
          }
          // 热水器：状态 / 当前水温 + 目标温度加减
          final WaterHeaterSummary? waterHeater = group.deviceId == null
              ? null
              : waterHeaters[group.deviceId];
          if (waterHeater != null) {
            final String entityId = waterHeater.entity.entityId;
            final double step = waterHeater.targetStep;
            void adjust(int direction) {
              final double base =
                  waterHeater.targetTemperature ?? waterHeater.minTemperature;
              context.read<HomeBloc>().add(
                SetWaterHeaterTemperature(
                  entityId: entityId,
                  temperature: base + direction * step,
                ),
              );
            }

            return WaterHeaterWidget(
              entity: waterHeater.entity,
              statusLabel: waterHeater.statusLabel,
              areaLabel: areaLabel,
              showAreaInTitle: state.selectedAreaId.isEmpty,
              isToggling: state.togglingIds.contains(entityId),
              onToggle: () => context.read<HomeBloc>().add(
                ToggleEntity(entityId: entityId),
              ),
              onIncrease: () => adjust(1),
              onDecrease: () => adjust(-1),
              onOpenDetail: () => Injection.get<AppRouter>().push(
                RouteNames.deviceDetailPath(group.deviceId!),
              ),
            );
          }

          // 洗衣机：状态 / 剩余时间 / 累计统计 + 真正的电源开关
          final WasherSummary? washer = group.deviceId == null
              ? null
              : washers[group.deviceId];
          if (washer != null) {
            final String powerId =
                washer.powerEntityId ??
                group.primary?.entityId ??
                group.entities.first.entityId;
            return WasherWidget(
              summary: washer,
              areaLabel: areaLabel,
              showAreaInTitle: state.selectedAreaId.isEmpty,
              isToggling: state.togglingIds.contains(powerId),
              onToggle: () =>
                  context.read<HomeBloc>().add(ToggleEntity(entityId: powerId)),
              onOpenDetail: () => Injection.get<AppRouter>().push(
                RouteNames.deviceDetailPath(group.deviceId!),
              ),
            );
          }

          // 含空调的设备：直接用温度卡（可进详情控制其余实体）
          final HaEntityStateModel? climate = group.climate;
          if (climate != null) {
            final bool toggling = state.togglingIds.contains(climate.entityId);
            final double step = climate.targetTempStep;
            void adjust(int direction) {
              final double base =
                  climate.targetTemperature ?? climate.minTargetTemperature;
              context.read<HomeBloc>().add(
                SetClimateTemperature(
                  entityId: climate.entityId,
                  temperature: base + direction * step,
                ),
              );
            }

            return ClimateWidget(
              entity: climate,
              isToggling: toggling,
              areaLabel: state.areaLabelFor(climate.entityId),
              showAreaInTitle: state.selectedAreaId.isEmpty,
              powerWatts: group.deviceId == null
                  ? null
                  : (state.powerStats[group.deviceId]?.acPowerWatts ??
                        state.powerStats[group.deviceId]?.currentWatts),
              onToggle: () => context.read<HomeBloc>().add(
                ToggleEntity(entityId: climate.entityId),
              ),
              onIncrease: () => adjust(1),
              onDecrease: () => adjust(-1),
              onOpenDetail: group.deviceId == null
                  ? null
                  : () => Injection.get<AppRouter>().push(
                      RouteNames.deviceDetailPath(group.deviceId!),
                    ),
            );
          }

          // 单实体设备：可开关 → 点击即开关；数据 / 动作 / 不可用 → 静态展示
          if (!group.isMerged) {
            final HaEntityStateModel entity =
                group.primary ?? group.entities.first;
            if (!entity.isSwitchable) {
              return ValueWidget(
                entity: entity,
                areaLabel: areaLabel,
                showAreaInTitle: state.selectedAreaId.isEmpty,
              );
            }
            final bool toggling = state.togglingIds.contains(entity.entityId);
            void onTap() => context.read<HomeBloc>().add(
              ToggleEntity(entityId: entity.entityId),
            );
            if (entity.domain == 'light') {
              return LightWidget(
                entity: entity,
                isToggling: toggling,
                onToggle: onTap,
                areaLabel: areaLabel,
                showAreaInTitle: state.selectedAreaId.isEmpty,
                onBrightnessChanged: (int percent) =>
                    context.read<HomeBloc>().add(
                      SetLightBrightness(
                        entityId: entity.entityId,
                        percent: percent,
                      ),
                    ),
              );
            }
            return ButtonWidget(
              entity: entity,
              isToggling: toggling,
              onToggle: onTap,
              areaLabel: areaLabel,
              showAreaInTitle: state.selectedAreaId.isEmpty,
            );
          }

          // 多实体设备：电源键切主实体（若有），点卡片进详情页
          final HaEntityStateModel? primary = group.primary;
          return DeviceWidget(
            group: group,
            isToggling:
                primary != null && group.isTogglingIn(state.togglingIds),
            areaLabel: areaLabel,
            showAreaInTitle: state.selectedAreaId.isEmpty,
            onTogglePrimary: () {
              if (primary != null) {
                context.read<HomeBloc>().add(
                  ToggleEntity(entityId: primary.entityId),
                );
              }
            },
            onOpenDetail: () => Injection.get<AppRouter>().push(
              RouteNames.deviceDetailPath(group.deviceId!),
            ),
            onBrightnessChanged:
                primary != null && primary.isLight && primary.supportsBrightness
                ? (int percent) => context.read<HomeBloc>().add(
                    SetLightBrightness(
                      entityId: primary.entityId,
                      percent: percent,
                    ),
                  )
                : null,
          );
        }

        return ReorderableBuilder.builder(
          itemCount: groups.length,
          scrollController: _scrollController,
          onReorderPositions: (positions) {
            final List<String> keys = groups
                .map((HaDeviceGroup group) => group.orderKey)
                .toList(growable: true);
            for (final position in positions) {
              if (position.oldIndex < 0 || position.oldIndex >= keys.length) {
                continue;
              }
              final String key = keys.removeAt(position.oldIndex);
              final int newIndex = position.newIndex
                  .clamp(0, keys.length)
                  .toInt();
              keys.insert(newIndex, key);
            }
            context.read<HomeBloc>().add(
              ReorderCards(
                visibleKeys: keys,
                homeName: state.effectiveHomeName,
              ),
            );
          },
          childBuilder: (wrapItem) {
            return GridView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 240,
                mainAxisExtent: 112,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: groups.length,
              itemBuilder: (BuildContext context, int index) {
                final HaDeviceGroup group = groups[index];
                return wrapItem(
                  KeyedSubtree(
                    key: ValueKey<String>(group.orderKey),
                    child: buildCard(context, index),
                  ),
                  index,
                );
              },
            );
          },
        );
      },
    );
  }
}

/// 设备加载失败页：保留错误原因，并提供立即重试入口。
class _HomeLoadError extends StatelessWidget {
  const _HomeLoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.cloud_off_rounded,
              size: 48,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text('设备加载失败', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              key: const Key('home_retry_load'),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('重试'),
            ),
            const SizedBox(height: 8),
            Text(
              '会自动重试，也可以立即重连',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
