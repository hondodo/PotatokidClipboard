import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pscreen_home/features/home/application/bloc/home_bloc.dart';
import 'package:pscreen_home/features/home/application/bloc/home_event.dart';
import 'package:pscreen_home/features/home/application/bloc/home_state.dart';
import 'package:pscreen_home/features/home/domain/models/ha_device_group.dart';
import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';
import 'package:pscreen_home/features/home/presentation/components/button_widget.dart';
import 'package:pscreen_home/features/home/presentation/components/light_widget.dart';

/// 设备详情页：一个物理设备的全部可控实体，逐实体开关。
///
/// 从首页网格的合并卡片点入（路由 /device/:deviceId）。
/// 外层只留必要详情与主控快捷键，被折叠的次要实体
/// （延时、勿扰、墙壁开关等）在这里展开单独控制。
class DeviceDetailPage extends StatelessWidget {
  const DeviceDetailPage({super.key, required this.deviceId});

  final String deviceId;

  @override
  Widget build(BuildContext context) {
    return BlocListener<HomeBloc, HomeState>(
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
      child: BlocBuilder<HomeBloc, HomeState>(
        builder: (BuildContext context, HomeState state) {
          final HaDeviceGroup? group = state.deviceGroupOf(deviceId);
          if (group == null) {
            return Scaffold(
              appBar: AppBar(title: const Text('设备详情')),
              body: const Center(child: Text('设备不存在或已移除')),
            );
          }
          return Scaffold(
            appBar: AppBar(
              title: Text(group.title),
              actions: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Center(
                    child: Text(
                      '${group.onCount}/${group.entities.length} 已开启',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                ),
              ],
            ),
            body: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: group.entities.length,
              separatorBuilder: (BuildContext context, int index) =>
                  const SizedBox(height: 12),
              itemBuilder: (BuildContext context, int index) {
                final HaEntityStateModel entity = group.entities[index];
                final bool toggling =
                    state.togglingIds.contains(entity.entityId);
                void onTap() => context
                    .read<HomeBloc>()
                    .add(ToggleEntity(entityId: entity.entityId));
                final String areaLabel =
                    state.areaLabelFor(entity.entityId);
                // 灯用暖黄光晕样式，其余用普通按钮卡
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
            ),
          );
        },
      ),
    );
  }
}
