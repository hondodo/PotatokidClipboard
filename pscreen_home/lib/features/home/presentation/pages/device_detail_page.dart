import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pscreen_home/features/home/application/bloc/home_bloc.dart';
import 'package:pscreen_home/features/home/application/bloc/home_event.dart';
import 'package:pscreen_home/features/home/application/bloc/home_state.dart';
import 'package:pscreen_home/features/home/domain/models/ha_device_group.dart';
import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';
import 'package:pscreen_home/features/home/domain/models/kettle_summary.dart';
import 'package:pscreen_home/features/home/domain/models/washer_summary.dart';
import 'package:pscreen_home/features/home/domain/models/water_heater_summary.dart';
import 'package:pscreen_home/features/home/presentation/components/button_widget.dart';
import 'package:pscreen_home/features/home/presentation/components/climate_control_panel.dart';
import 'package:pscreen_home/features/home/presentation/components/kettle_control_panel.dart';
import 'package:pscreen_home/features/home/presentation/components/light_control_panel.dart';
import 'package:pscreen_home/features/home/presentation/components/value_widget.dart';
import 'package:pscreen_home/features/home/presentation/components/washer_control_panel.dart';
import 'package:pscreen_home/features/home/presentation/components/water_heater_control_panel.dart';
import 'package:pscreen_home/features/home/presentation/components/water_heater_schedule_sheet.dart';
import 'package:pscreen_home/features/home/presentation/components/water_usage_sheet.dart';

/// 设备详情页：一个物理设备的全部可控实体。
///
/// 灯 / 空调渲染成完整控制面板（亮度、色温、效果 / 温度盘、模式、风速、
/// 摆风），其余实体（延时、勿扰、墙壁开关等）保持轻量开关卡。
/// 从首页网格的合并卡片点入（路由 /device/:deviceId）。
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

          final WasherSummary? washer = state.washerSummaries[deviceId];
          final WaterHeaterSummary? waterHeater =
              state.waterHeaterSummaries[deviceId];
          final KettleSummary? kettle = state.kettleSummaries[deviceId];
          final String washerPowerId = washer?.powerEntityId ??
              group.primary?.entityId ??
              group.entities.first.entityId;
          final Set<String> hiddenIds = <String>{
            if (washer?.powerEntityId != null) washer!.powerEntityId!,
            if (washer?.modeEntityId != null) washer!.modeEntityId!,
            if (washer?.startEntityId != null) washer!.startEntityId!,
            if (washer?.pauseEntityId != null) washer!.pauseEntityId!,
            if (washer?.stopEntityId != null) washer!.stopEntityId!,
            if (waterHeater != null) waterHeater.entity.entityId,
            if (waterHeater?.preheatEntityId != null)
              waterHeater!.preheatEntityId!,
            if (waterHeater?.timerPreheatEntityId != null)
              waterHeater!.timerPreheatEntityId!,
            if (waterHeater?.scheduleEntityId != null)
              waterHeater!.scheduleEntityId!,
            if (waterHeater?.usageEntityId != null)
              waterHeater!.usageEntityId!,
            if (kettle?.modeEntityId != null) kettle!.modeEntityId!,
            if (kettle?.targetEntityId != null) kettle!.targetEntityId!,
            if (kettle?.keepWarmEntityId != null) kettle!.keepWarmEntityId!,
            if (kettle?.keepWarmTempEntityId != null)
              kettle!.keepWarmTempEntityId!,
            if (kettle?.dechlorinationEntityId != null)
              kettle!.dechlorinationEntityId!,
            if (kettle?.rapidCoolingEntityId != null)
              kettle!.rapidCoolingEntityId!,
            if (kettle?.startEntityId != null) kettle!.startEntityId!,
            if (kettle?.stopEntityId != null) kettle!.stopEntityId!,
          };
          final List<HaEntityStateModel> entities = group.entities
              .where((HaEntityStateModel e) => !hiddenIds.contains(e.entityId))
              .toList(growable: false);
          final int panelCount =
              washer == null && waterHeater == null && kettle == null ? 0 : 1;
          final String headerStatus;
          if (washer != null) {
            headerStatus =
                washer.hasFault ? '故障' : washer.statusLabel;
          } else if (waterHeater != null) {
            headerStatus =
                waterHeater.hasFault ? '故障' : waterHeater.statusLabel;
          } else if (kettle != null) {
            headerStatus = kettle.hasFault ? '故障' : kettle.status;
          } else {
            headerStatus = group.statusLabel;
          }

          return Scaffold(
            appBar: AppBar(
              title: Text(group.title),
              actions: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 240),
                      child: Text(
                        headerStatus,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            body: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: entities.length + panelCount,
              separatorBuilder: (BuildContext context, int index) =>
                  const SizedBox(height: 12),
              itemBuilder: (BuildContext context, int index) {
                if (washer != null && index == 0) {
                  return WasherControlPanel(
                    summary: washer,
                    isToggling: state.togglingIds.contains(washerPowerId),
                    onToggle: () => context
                        .read<HomeBloc>()
                        .add(ToggleEntity(entityId: washerPowerId)),
                    onModeSelected: (String mode) {
                      final String? modeId = washer.modeEntityId;
                      if (modeId == null) return;
                      context.read<HomeBloc>().add(
                            SelectEntityOption(
                              entityId: modeId,
                              option: mode,
                            ),
                          );
                    },
                    onStart: washer.startEntityId == null
                        ? null
                        : () => context.read<HomeBloc>().add(
                              PressEntityButton(
                                entityId: washer.startEntityId!,
                              ),
                            ),
                    onPause: washer.pauseEntityId == null
                        ? null
                        : () => context.read<HomeBloc>().add(
                              PressEntityButton(
                                entityId: washer.pauseEntityId!,
                              ),
                            ),
                    onStop: washer.stopEntityId == null
                        ? null
                        : () => context.read<HomeBloc>().add(
                              PressEntityButton(
                                entityId: washer.stopEntityId!,
                              ),
                            ),
                  );
                }

                if (kettle != null && index == 0) {
                  return KettleControlPanel(
                    summary: kettle,
                    isBusy: false,
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
                              PressEntityButton(
                                entityId: kettle.stopEntityId!,
                              ),
                            ),
                    onModeSelected: kettle.modeEntityId == null
                        ? null
                        : (String mode) => context.read<HomeBloc>().add(
                              SelectEntityOption(
                                entityId: kettle.modeEntityId!,
                                option: mode,
                              ),
                            ),
                    onTargetTemperatureChanged:
                        kettle.targetEntityId == null
                            ? null
                            : (double value) => context
                                .read<HomeBloc>()
                                .add(SetNumberEntityValue(
                                  entityId: kettle.targetEntityId!,
                                  value: value,
                                )),
                    onKeepWarmTemperatureChanged:
                        kettle.effectiveKeepWarmTempEntityId == null
                            ? null
                            : (double value) => context
                                .read<HomeBloc>()
                                .add(SetNumberEntityValue(
                                  entityId:
                                      kettle.effectiveKeepWarmTempEntityId!,
                                  value: value,
                                )),
                    onToggleKeepWarm: kettle.keepWarmEntityId == null
                        ? null
                        : () => context.read<HomeBloc>().add(ToggleEntity(
                              entityId: kettle.keepWarmEntityId!,
                            )),
                    onToggleDechlorination:
                        kettle.dechlorinationEntityId == null
                            ? null
                            : () => context.read<HomeBloc>().add(ToggleEntity(
                                  entityId: kettle.dechlorinationEntityId!,
                                )),
                    onToggleRapidCooling:
                        kettle.rapidCoolingEntityId == null
                            ? null
                            : () => context.read<HomeBloc>().add(ToggleEntity(
                                  entityId: kettle.rapidCoolingEntityId!,
                                )),
                  );
                }

                if (waterHeater != null && index == 0) {
                  final String entityId = waterHeater.entity.entityId;
                  final String? preheatId = waterHeater.preheatEntityId;
                  final String? timerId = waterHeater.timerPreheatEntityId;
                  return WaterHeaterControlPanel(
                    summary: waterHeater,
                    isToggling: state.togglingIds.contains(entityId),
                    onToggle: () => context
                        .read<HomeBloc>()
                        .add(ToggleEntity(entityId: entityId)),
                    onTemperatureChanged: (double value) => context
                        .read<HomeBloc>()
                        .add(SetWaterHeaterTemperature(
                          entityId: entityId,
                          temperature: value,
                        )),
                    onModeSelected: (String mode) => context
                        .read<HomeBloc>()
                        .add(SetWaterHeaterOperationMode(
                          entityId: entityId,
                          mode: mode,
                        )),
                    onPreheatToggle: preheatId == null
                        ? null
                        : () => context
                            .read<HomeBloc>()
                            .add(ToggleEntity(entityId: preheatId)),
                    onTimerPreheatToggle: timerId == null
                        ? null
                        : () => context
                            .read<HomeBloc>()
                            .add(ToggleEntity(entityId: timerId)),
                    onShowUsage: waterHeater.usageEntityId == null
                        ? null
                        : () => showModalBottomSheet<void>(
                              context: context,
                              isScrollControlled: true,
                              useSafeArea: true,
                              builder: (BuildContext sheetContext) =>
                                  FractionallySizedBox(
                                heightFactor: 0.92,
                                child: WaterUsageSheet(
                                  entityId: waterHeater.usageEntityId!,
                                  title: waterHeater.name,
                                ),
                              ),
                            ),
                    onEditSchedule: waterHeater.scheduleEntityId == null
                        ? null
                        : () => showModalBottomSheet<void>(
                              context: context,
                              isScrollControlled: true,
                              useSafeArea: true,
                              builder: (BuildContext sheetContext) =>
                                  FractionallySizedBox(
                                heightFactor: 0.9,
                                child: WaterHeaterScheduleSheet(
                                  scheduleText: waterHeater.scheduleText,
                                  masterOn: waterHeater.timerPreheatOn,
                                  onWrite: (String value) => context
                                      .read<HomeBloc>()
                                      .add(SetTextEntityValue(
                                        entityId:
                                            waterHeater.scheduleEntityId!,
                                        value: value,
                                      )),
                                  onMasterToggle: timerId == null
                                      ? null
                                      : () => context
                                          .read<HomeBloc>()
                                          .add(ToggleEntity(entityId: timerId)),
                                ),
                              ),
                            ),
                  );
                }

                final HaEntityStateModel entity =
                    entities[index - panelCount];
                final bool toggling =
                    state.togglingIds.contains(entity.entityId);
                final String areaLabel = state.areaLabelFor(entity.entityId);
                void onToggle() => context
                    .read<HomeBloc>()
                    .add(ToggleEntity(entityId: entity.entityId));

                if (entity.isClimate) {
                  return ClimateControlPanel(
                    entity: entity,
                    isToggling: toggling,
                    areaLabel: areaLabel,
                    onToggle: onToggle,
                    onTemperatureChanged: (double value) => context
                        .read<HomeBloc>()
                        .add(SetClimateTemperature(
                          entityId: entity.entityId,
                          temperature: value,
                        )),
                    onHvacModeSelected: (String mode) => context
                        .read<HomeBloc>()
                        .add(SetClimateHvacMode(
                          entityId: entity.entityId,
                          mode: mode,
                        )),
                    onFanModeSelected: (String mode) => context
                        .read<HomeBloc>()
                        .add(SetClimateFanMode(
                          entityId: entity.entityId,
                          mode: mode,
                        )),
                    onSwingModeSelected: (String mode) => context
                        .read<HomeBloc>()
                        .add(SetClimateSwingMode(
                          entityId: entity.entityId,
                          mode: mode,
                        )),
                  );
                }

                if (entity.isLight) {
                  return LightControlPanel(
                    entity: entity,
                    isToggling: toggling,
                    areaLabel: areaLabel,
                    onToggle: onToggle,
                    onBrightnessChanged: (int percent) => context
                        .read<HomeBloc>()
                        .add(SetLightBrightness(
                          entityId: entity.entityId,
                          percent: percent,
                        )),
                    onColorTemperatureChanged: (int kelvin) => context
                        .read<HomeBloc>()
                        .add(SetLightColorTemperature(
                          entityId: entity.entityId,
                          kelvin: kelvin,
                        )),
                    onEffectSelected: (String effect) => context
                        .read<HomeBloc>()
                        .add(SetLightEffect(
                          entityId: entity.entityId,
                          effect: effect,
                        )),
                  );
                }

                if (!entity.isSwitchable) {
                  return ValueWidget(entity: entity, areaLabel: areaLabel);
                }

                return ButtonWidget(
                  entity: entity,
                  isToggling: toggling,
                  onToggle: onToggle,
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
