import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pscreen_home/core/network/ha_ws_client.dart';
import 'package:pscreen_home/features/connection/application/bloc/connection_bloc.dart';
import 'package:pscreen_home/features/connection/application/bloc/connection_event.dart';
import 'package:pscreen_home/features/connection/application/bloc/connection_state.dart';
import 'package:pscreen_home/features/home/application/bloc/home_bloc.dart';
import 'package:pscreen_home/features/home/application/bloc/home_event.dart';
import 'package:pscreen_home/features/home/application/bloc/home_state.dart';
import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';
import 'package:pscreen_home/features/home/domain/models/ha_registry_model.dart';
import 'package:pscreen_home/features/home/presentation/components/button_widget.dart';
import 'package:pscreen_home/features/home/presentation/components/light_widget.dart';

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
          actions: const <Widget>[_ConnectionStatus()],
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
            _HomeBar(),
            _AreaBar(),
            Expanded(child: _ControlGrid()),
          ],
        );
      },
    );
  }
}

/// 第一行：家庭标签（区域名前缀解析出的家庭分组，如「金科1204」）。
/// 仅当存在两个及以上家庭时展示。
class _HomeBar extends StatelessWidget {
  const _HomeBar();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<HomeBloc, HomeState>(
      builder: (BuildContext context, HomeState state) {
        final List<String> homes = state.availableHomes;
        if (homes.length <= 1) return const SizedBox.shrink();
        final String current = state.effectiveHomeName;
        return SizedBox(
          height: 52,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            itemCount: homes.length + 1,
            separatorBuilder: (BuildContext context, int index) =>
                const SizedBox(width: 8),
            itemBuilder: (BuildContext context, int index) {
              if (index == 0) {
                return ChoiceChip(
                  label: const Text('全部'),
                  selected: current.isEmpty,
                  onSelected: (_) => context
                      .read<HomeBloc>()
                      .add(const HomeSelected('')),
                );
              }
              final String home = homes[index - 1];
              return ChoiceChip(
                label: Text('${state.homeLabel(home)} ${state.homeCount(home)}'),
                selected: current == home,
                onSelected: (_) => context
                    .read<HomeBloc>()
                    .add(HomeSelected(home)),
              );
            },
          ),
        );
      },
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

/// 快捷控件网格：全部 light/switch 实体，灯在前、开关在后。
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

        final List<HaEntityStateModel> controls = state.quickControls;
        if (controls.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.lightbulb_outline_rounded,
                    size: 48, color: Colors.grey),
                SizedBox(height: 16),
                Text('没有找到可控制的灯或开关'),
              ],
            ),
          );
        }

        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 240,
            mainAxisExtent: 96,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: controls.length,
          itemBuilder: (BuildContext context, int index) {
            final HaEntityStateModel entity = controls[index];
            final bool toggling = state.togglingIds.contains(entity.entityId);
            final String areaLabel = state.areaLabelFor(entity.entityId);
            void onTap() => context
                .read<HomeBloc>()
                .add(ToggleEntity(entityId: entity.entityId));
            if (entity.domain == 'light') {
              return LightWidget(
                entity: entity,
                isToggling: toggling,
                onToggle: onTap,
                areaLabel: areaLabel,
              );
            }
            return ButtonWidget(
              entity: entity,
              isToggling: toggling,
              onToggle: onTap,
              areaLabel: areaLabel,
            );
          },
        );
      },
    );
  }
}
