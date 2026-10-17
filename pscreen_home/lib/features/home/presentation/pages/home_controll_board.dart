import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_bloc/flutter_bloc.dart';
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
import 'package:pscreen_home/features/home/domain/models/ha_device_group.dart';
import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';
import 'package:pscreen_home/features/home/domain/models/ha_registry_model.dart';
import 'package:pscreen_home/features/home/domain/models/home_climate_summary.dart';
import 'package:pscreen_home/features/home/domain/models/kettle_summary.dart';
import 'package:pscreen_home/features/home/domain/models/washer_summary.dart';
import 'package:pscreen_home/features/home/domain/models/water_heater_summary.dart';
import 'package:pscreen_home/features/home/presentation/components/button_widget.dart';
import 'package:pscreen_home/features/home/presentation/components/climate_display.dart';
import 'package:pscreen_home/features/home/presentation/components/climate_widget.dart';
import 'package:pscreen_home/features/home/presentation/components/device_widget.dart';
import 'package:pscreen_home/features/home/presentation/components/kettle_widget.dart';
import 'package:pscreen_home/features/home/presentation/components/light_widget.dart';
import 'package:pscreen_home/features/home/presentation/components/value_widget.dart';
import 'package:pscreen_home/features/home/presentation/components/washer_widget.dart';
import 'package:pscreen_home/features/home/presentation/components/water_heater_widget.dart';

/// 主页面：中控台。
///
/// 布局（对应原构想注释）：
/// - 顶部第一行：**家庭**标签（✅ 区域名前缀解析：薯仔4号的家 / 金科1204 / 棠德304）
/// - 第二行：**房间**标签（✅ 基于 area 注册表，受家庭筛选，后缀为可控实体数）
/// - 下方网格：按 家庭 ▸ 房间 两级过滤，卡片标注实体所属房间
/// - 待实现：常用设备横向列表（M3，设置页勾选常用实体）
class HomeControllBoard extends StatelessWidget {
  const HomeControllBoard({super.key});

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
        // 控制失败提示，展示后立即清除错误避免重复弹出
        BlocListener<HomeBloc, HomeState>(
          listenWhen: (HomeState prev, HomeState cur) =>
              cur.errorMessage != null && cur.errorMessage != prev.errorMessage,
          listener: (BuildContext context, HomeState state) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(
                  content: Text(state.errorMessage ?? ''),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            context.read<HomeBloc>().add(const ClearHomeError());
          },
        ),
      ],
      child: Scaffold(
        appBar: AppBar(
          title: const Text('中控台'),
          actions: <Widget>[
            const _ConnectionStatus(),
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
          HaConnectionPhase.authFailed =>
            (state.message ?? '认证失败', Colors.redAccent),
          HaConnectionPhase.disconnected =>
            (state.isRetrying ? '重连中…' : '未连接', Colors.redAccent),
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
                onPressed: () => context
                    .read<ConnectionBloc>()
                    .add(const RetryConnection()),
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
/// - 已选家庭：只显示所选家庭的摘要，并提供「全部」返回。
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
        final List<HomeClimateSummary> summaries =
            state.homeClimateSummaries;
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
                onShowAll: () => context
                    .read<HomeBloc>()
                    .add(const HomeSelected('')),
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
                onTap: () => context
                    .read<HomeBloc>()
                    .add(HomeSelected(summary.homeName)),
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
  const _SelectedHomeSummary({
    required this.summary,
    required this.onShowAll,
  });

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
    return Tooltip(
      message: '数据来源：$source',
      child: values,
    );
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
                  onSelected: (_) => context
                      .read<HomeBloc>()
                      .add(const AreaSelected('')),
                );
              }
              final HaArea area = areas[index - 1];
              // 已选家庭时房间名天然不重复，用短名；否则用完整区域名区分
              final String label =
                  scopedByHome ? area.roomName : area.name;
              return ChoiceChip(
                label: Text('$label ${state.areaCount(area.areaId)}'),
                selected: current == area.areaId,
                onSelected: (_) => context
                    .read<HomeBloc>()
                    .add(AreaSelected(area.areaId)),
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
    final bool connecting = state.phase == HaConnectionPhase.connecting ||
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
                  onPressed: () => context
                      .read<ConnectionBloc>()
                      .add(const RetryConnection()),
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
class _ControlGrid extends StatelessWidget {
  const _ControlGrid();

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

        final List<HaDeviceGroup> groups = state.deviceGroups;
        if (groups.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.lightbulb_outline_rounded,
                    size: 48, color: Colors.grey),
                SizedBox(height: 16),
                Text('没有找到实体'),
              ],
            ),
          );
        }

        final Map<String, WasherSummary> washers = state.washerSummaries;
        final Map<String, WaterHeaterSummary> waterHeaters =
            state.waterHeaterSummaries;
        final Map<String, KettleSummary> kettles = state.kettleSummaries;
        return GridView.builder(
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
            final String areaLabel = state.areaLabelFor(
              group.primary?.entityId ?? group.entities.first.entityId,
            );

            // 电热水瓶：当前水温 + 状态 + 模式 + 开始/停止
            final KettleSummary? kettle =
                group.deviceId == null ? null : kettles[group.deviceId];
            if (kettle != null) {
              return KettleWidget(
                summary: kettle,
                isBusy: false,
                onStart: kettle.startEntityId == null
                    ? null
                    : () => context.read<HomeBloc>().add(
                          PressNotifyAction(
                            entityId: kettle.startEntityId!,
                          ),
                        ),
                onStop: kettle.stopEntityId == null
                    ? null
                    : () => context.read<HomeBloc>().add(
                          PressEntityButton(
                            entityId: kettle.stopEntityId!,
                          ),
                        ),
                onOpenDetail: () => Injection.get<AppRouter>()
                    .push(RouteNames.deviceDetailPath(group.deviceId!)),
              );
            }
            // 热水器：状态 / 当前水温 + 目标温度加减
            final WaterHeaterSummary? waterHeater =
                group.deviceId == null ? null : waterHeaters[group.deviceId];
            if (waterHeater != null) {
              final String entityId = waterHeater.entity.entityId;
              final double step = waterHeater.targetStep;
              void adjust(int direction) {
                final double base = waterHeater.targetTemperature ??
                    waterHeater.minTemperature;
                context.read<HomeBloc>().add(SetWaterHeaterTemperature(
                      entityId: entityId,
                      temperature: base + direction * step,
                    ));
              }

              return WaterHeaterWidget(
                entity: waterHeater.entity,
                statusLabel: waterHeater.statusLabel,
                isToggling: state.togglingIds.contains(entityId),
                onToggle: () => context
                    .read<HomeBloc>()
                    .add(ToggleEntity(entityId: entityId)),
                onIncrease: () => adjust(1),
                onDecrease: () => adjust(-1),
                onOpenDetail: () => Injection.get<AppRouter>()
                    .push(RouteNames.deviceDetailPath(group.deviceId!)),
              );
            }

            // 洗衣机：状态 / 剩余时间 / 累计统计 + 真正的电源开关
            final WasherSummary? washer =
                group.deviceId == null ? null : washers[group.deviceId];
            if (washer != null) {
              final String powerId = washer.powerEntityId ??
                  group.primary?.entityId ??
                  group.entities.first.entityId;
              return WasherWidget(
                summary: washer,
                isToggling: state.togglingIds.contains(powerId),
                onToggle: () => context
                    .read<HomeBloc>()
                    .add(ToggleEntity(entityId: powerId)),
                onOpenDetail: () => Injection.get<AppRouter>()
                    .push(RouteNames.deviceDetailPath(group.deviceId!)),
              );
            }

            // 含空调的设备：直接用温度卡（可进详情控制其余实体）
            final HaEntityStateModel? climate = group.climate;
            if (climate != null) {
              final bool toggling =
                  state.togglingIds.contains(climate.entityId);
              final double step = climate.targetTempStep;
              void adjust(int direction) {
                final double base =
                    climate.targetTemperature ?? climate.minTargetTemperature;
                context.read<HomeBloc>().add(SetClimateTemperature(
                      entityId: climate.entityId,
                      temperature: base + direction * step,
                    ));
              }

              return ClimateWidget(
                entity: climate,
                isToggling: toggling,
                areaLabel: state.areaLabelFor(climate.entityId),
                onToggle: () => context
                    .read<HomeBloc>()
                    .add(ToggleEntity(entityId: climate.entityId)),
                onIncrease: () => adjust(1),
                onDecrease: () => adjust(-1),
                onOpenDetail: group.deviceId == null
                    ? null
                    : () => Injection.get<AppRouter>()
                        .push(RouteNames.deviceDetailPath(group.deviceId!)),
              );
            }

            // 单实体设备：可开关 → 点击即开关；数据 / 动作 / 不可用 → 静态展示
            if (!group.isMerged) {
              final HaEntityStateModel entity =
                  group.primary ?? group.entities.first;
              if (!entity.isSwitchable) {
                return ValueWidget(entity: entity, areaLabel: areaLabel);
              }
              final bool toggling =
                  state.togglingIds.contains(entity.entityId);
              void onTap() => context
                  .read<HomeBloc>()
                  .add(ToggleEntity(entityId: entity.entityId));
              if (entity.domain == 'light') {
                return LightWidget(
                  entity: entity,
                  isToggling: toggling,
                  onToggle: onTap,
                  areaLabel: areaLabel,
                  onBrightnessChanged: (int percent) => context
                      .read<HomeBloc>()
                      .add(SetLightBrightness(
                        entityId: entity.entityId,
                        percent: percent,
                      )),
                );
              }
              return ButtonWidget(
                entity: entity,
                isToggling: toggling,
                onToggle: onTap,
                areaLabel: areaLabel,
              );
            }

            // 多实体设备：电源键切主实体（若有），点卡片进详情页
            final HaEntityStateModel? primary = group.primary;
            return DeviceWidget(
              group: group,
              isToggling: primary != null &&
                  group.isTogglingIn(state.togglingIds),
              areaLabel: areaLabel,
              onTogglePrimary: () {
                if (primary != null) {
                  context
                      .read<HomeBloc>()
                      .add(ToggleEntity(entityId: primary.entityId));
                }
              },
              onOpenDetail: () => Injection.get<AppRouter>()
                  .push(RouteNames.deviceDetailPath(group.deviceId!)),
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
          },
        );
      },
    );
  }
}
