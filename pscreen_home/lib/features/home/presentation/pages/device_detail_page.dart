import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pscreen_home/features/home/application/bloc/home_bloc.dart';
import 'package:pscreen_home/features/home/application/bloc/home_event.dart';
import 'package:pscreen_home/features/home/application/bloc/home_state.dart';
import 'package:pscreen_home/features/home/domain/models/ha_device_group.dart';
import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';
import 'package:pscreen_home/features/home/domain/models/air_fryer_summary.dart';
import 'package:pscreen_home/features/home/domain/models/fan_summary.dart';
import 'package:pscreen_home/features/home/domain/models/fridge_summary.dart';
import 'package:pscreen_home/features/home/domain/models/kettle_summary.dart';
import 'package:pscreen_home/features/home/domain/models/projector_summary.dart';
import 'package:pscreen_home/features/home/domain/models/multi_switch_summary.dart';
import 'package:pscreen_home/features/home/domain/models/power_stats.dart';
import 'package:pscreen_home/features/home/domain/models/rice_cooker_summary.dart';
import 'package:pscreen_home/features/home/domain/models/socket_summary.dart';
import 'package:pscreen_home/features/home/domain/models/washer_summary.dart';
import 'package:pscreen_home/features/home/domain/models/water_heater_summary.dart';
import 'package:pscreen_home/features/home/presentation/components/button_widget.dart';
import 'package:pscreen_home/features/home/presentation/components/air_fryer_control_panel.dart';
import 'package:pscreen_home/features/home/presentation/components/climate_control_panel.dart';
import 'package:pscreen_home/features/home/presentation/components/fan_control_panel.dart';
import 'package:pscreen_home/features/home/presentation/components/fan_light_widget.dart';
import 'package:pscreen_home/features/home/presentation/components/fridge_control_panel.dart';
import 'package:pscreen_home/features/home/presentation/components/kettle_control_panel.dart';
import 'package:pscreen_home/features/home/presentation/components/light_control_panel.dart';
import 'package:pscreen_home/features/home/presentation/components/projector_control_panel.dart';
import 'package:pscreen_home/features/home/presentation/components/projector_remote_sheet.dart';
import 'package:pscreen_home/features/home/presentation/components/rice_cooker_control_panel.dart';
import 'package:pscreen_home/features/home/presentation/components/power_stats_card.dart';
import 'package:pscreen_home/features/home/presentation/components/multi_switch_control_panel.dart';
import 'package:pscreen_home/features/home/presentation/components/socket_control_panel.dart';
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
          final FanSummary? fan = state.fanSummaries[deviceId];
          final ProjectorSummary? projector =
              state.projectorSummaries[deviceId];
          final bool showProjectorPanel = projector != null;
          final FridgeSummary? fridge = state.fridgeSummaries[deviceId];
          final bool showFridgePanel = fridge != null;
          final SocketSummary? socket = state.socketSummaries[deviceId];
          final bool showSocketPanel = socket != null;
          final PowerStats? devicePower = state.powerStats[deviceId];
          final MultiSwitchSummary? multiSwitch =
              state.multiSwitchSummaries[deviceId];
          final bool showMultiSwitchPanel = multiSwitch != null;
          final RiceCookerSummary? riceCooker =
              state.riceCookerSummaries[deviceId];
          final bool showRiceCookerPanel = riceCooker != null;
          final AirFryerSummary? airFryer =
              state.airFryerSummaries[deviceId];
          final bool showAirFryerPanel = airFryer != null;
          final bool showFanPanel = fan != null;
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
            if (showFanPanel) fan.entity.entityId,
            if (showFanPanel && fan.delayEntityId != null)
              fan.delayEntityId!,
            if (showFanPanel && fan.masterSwitchEntityId != null)
              fan.masterSwitchEntityId!,
            if (showProjectorPanel)
              for (final HaEntityStateModel entity in group.entities)
                entity.entityId,
            if (showFridgePanel)
              for (final HaEntityStateModel entity in group.entities)
                entity.entityId,
            if (showSocketPanel)
              for (final HaEntityStateModel entity in group.entities)
                entity.entityId,
            if (devicePower?.currentEntityId != null)
              devicePower!.currentEntityId!,
            if (devicePower?.totalEntityId != null)
              devicePower!.totalEntityId!,
            if (devicePower?.temperatureEntityId != null)
              devicePower!.temperatureEntityId!,
            if (devicePower?.countEntityId != null)
              devicePower!.countEntityId!,
            if (showMultiSwitchPanel)
              for (final SwitchGang gang in multiSwitch.gangs)
                gang.entityId,
            if (showRiceCookerPanel)
              for (final HaEntityStateModel entity in group.entities)
                entity.entityId,
            if (showAirFryerPanel)
              for (final HaEntityStateModel entity in group.entities)
                entity.entityId,
          };
          final List<HaEntityStateModel> entities = group.entities
              .where((HaEntityStateModel e) => !hiddenIds.contains(e.entityId))
              .toList(growable: false);
          final int panelCount = washer == null &&
                  waterHeater == null &&
                  kettle == null &&
                  !showFanPanel &&
                  !showProjectorPanel &&
                  !showFridgePanel &&
                  !showSocketPanel &&
                  !showMultiSwitchPanel &&
                  !showRiceCookerPanel &&
                  !showAirFryerPanel
              ? 0
              : 1;
          final String headerStatus;
          if (washer != null) {
            headerStatus =
                washer.hasFault ? '故障' : washer.statusLabel;
          } else if (waterHeater != null) {
            headerStatus =
                waterHeater.hasFault ? '故障' : waterHeater.statusLabel;
          } else if (kettle != null) {
            headerStatus = kettle.hasFault ? '故障' : kettle.status;
          } else if (showFanPanel) {
            headerStatus = fan.statusLabel;
          } else if (showProjectorPanel) {
            headerStatus = projector.title;
          } else if (showFridgePanel) {
            headerStatus = fridge.statusLabel;
          } else if (showSocketPanel) {
            headerStatus = socket.statusLabel;
          } else if (showMultiSwitchPanel) {
            headerStatus = multiSwitch.statusLabel;
          } else if (showRiceCookerPanel) {
            headerStatus = riceCooker.status;
          } else if (showAirFryerPanel) {
            headerStatus = airFryer.status;
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
                if (showRiceCookerPanel && index == 0) {
                  final RiceCookerSummary current = riceCooker;
                  return RiceCookerControlPanel(
                    summary: current,
                    onStart: current.startEntityId == null
                        ? null
                        : () => context.read<HomeBloc>().add(
                              PressNotifyAction(
                                entityId: current.startEntityId!,
                                message: current.startMessage,
                              ),
                            ),
                    onStop: current.stopEntityId == null
                        ? null
                        : () => context.read<HomeBloc>().add(
                              PressEntityButton(
                                entityId: current.stopEntityId!,
                              ),
                            ),
                  );
                }

                if (showAirFryerPanel && index == 0) {
                  final AirFryerSummary current = airFryer;
                  return AirFryerControlPanel(
                    summary: current,
                    onModeSelected: current.modeEntityId == null
                        ? (_) {}
                        : (String mode) => context.read<HomeBloc>().add(
                              SelectEntityOption(
                                entityId: current.modeEntityId!,
                                option: mode,
                              ),
                            ),
                    onTemperatureChanged:
                        current.temperatureEntityId == null
                            ? (_) {}
                            : (int value) => context.read<HomeBloc>().add(
                                  SetNumberEntityValue(
                                    entityId:
                                        current.temperatureEntityId!,
                                    value: value.toDouble(),
                                  ),
                                ),
                    onTimeChanged: current.timeEntityId == null
                        ? (_) {}
                        : (int value) => context.read<HomeBloc>().add(
                              SetNumberEntityValue(
                                entityId: current.timeEntityId!,
                                value: value.toDouble(),
                              ),
                            ),
                    onStart: current.startEntityId == null
                        ? null
                        : () => context.read<HomeBloc>().add(
                              PressEntityButton(
                                entityId: current.startEntityId!,
                              ),
                            ),
                    onPause: current.pauseEntityId == null
                        ? null
                        : () => context.read<HomeBloc>().add(
                              PressEntityButton(
                                entityId: current.pauseEntityId!,
                              ),
                            ),
                    onResume: current.resumeEntityId == null
                        ? null
                        : () => context.read<HomeBloc>().add(
                              PressEntityButton(
                                entityId: current.resumeEntityId!,
                              ),
                            ),
                    onStop: current.stopEntityId == null
                        ? null
                        : () => context.read<HomeBloc>().add(
                              PressEntityButton(
                                entityId: current.stopEntityId!,
                              ),
                            ),
                    onAutoKeepWarm:
                        current.autoKeepWarmEntityId == null
                            ? null
                            : () => context.read<HomeBloc>().add(
                                  ToggleEntity(
                                    entityId:
                                        current.autoKeepWarmEntityId!,
                                  ),
                                ),
                    onCurrentKeepWarm:
                        current.currentKeepWarmEntityId == null
                            ? null
                            : () => context.read<HomeBloc>().add(
                                  ToggleEntity(
                                    entityId:
                                        current.currentKeepWarmEntityId!,
                                  ),
                                ),
                  );
                }

                if (showMultiSwitchPanel && index == 0) {
                  final MultiSwitchSummary current = multiSwitch;
                  return MultiSwitchControlPanel(
                    summary: current,
                    togglingIds: state.togglingIds,
                    onToggleGang: (String entityId) =>
                        context.read<HomeBloc>().add(
                              ToggleEntity(entityId: entityId),
                            ),
                    onAllOn: () {
                      for (final SwitchGang gang in current.gangs) {
                        if (!gang.isOn) {
                          context
                              .read<HomeBloc>()
                              .add(ToggleEntity(entityId: gang.entityId));
                        }
                      }
                    },
                    onAllOff: () {
                      for (final SwitchGang gang in current.gangs) {
                        if (gang.isOn) {
                          context
                              .read<HomeBloc>()
                              .add(ToggleEntity(entityId: gang.entityId));
                        }
                      }
                    },
                  );
                }

                if (showSocketPanel && index == 0) {
                  return SocketControlPanel(
                    summary: socket,
                    isToggling: state.togglingIds
                        .contains(socket.powerEntityId),
                    onToggle: () => context.read<HomeBloc>().add(
                          ToggleEntity(
                            entityId: socket.powerEntityId,
                          ),
                        ),
                  );
                }

                if (showFridgePanel && index == 0) {
                  final FridgeSummary current = fridge;
                  return FridgeControlPanel(
                    summary: current,
                    onModeSelected: current.modeEntityId == null
                        ? (_) {}
                        : (String mode) => context.read<HomeBloc>().add(
                              SelectEntityOption(
                                entityId: current.modeEntityId!,
                                option: mode,
                              ),
                            ),
                    onTargetChanged:
                        (String entityId, int temperature) =>
                            context.read<HomeBloc>().add(
                                  SetNumberEntityValue(
                                    entityId: entityId,
                                    value: temperature.toDouble(),
                                  ),
                                ),
                  );
                }

                if (showProjectorPanel && index == 0) {
                  final ProjectorSummary current = projector;
                  final String? powerId = current.isOn
                      ? current.powerOffEntityId
                      : current.powerOnEntityId;
                  return ProjectorControlPanel(
                    summary: current,
                    isBusy: powerId != null &&
                        state.togglingIds.contains(powerId),
                    onPower: powerId == null
                        ? () {}
                        : () => context.read<HomeBloc>().add(
                              PressEntityButton(entityId: powerId),
                            ),
                    onVolumeChanged: current.volumeEntityId == null
                        ? (_) {}
                        : (int value) => context.read<HomeBloc>().add(
                              SetNumberEntityValue(
                                entityId: current.volumeEntityId!,
                                value: value.toDouble(),
                              ),
                            ),
                    onBrightnessChanged:
                        current.brightnessEntityId == null
                            ? (_) {}
                            : (int value) => context.read<HomeBloc>().add(
                                  SetNumberEntityValue(
                                    entityId:
                                        current.brightnessEntityId!,
                                    value: value.toDouble(),
                                  ),
                                ),
                    onInputSelected: current.inputEntityId == null
                        ? (_) {}
                        : (String input) => context.read<HomeBloc>().add(
                              SelectEntityOption(
                                entityId: current.inputEntityId!,
                                option: input,
                              ),
                            ),
                    onMuteToggle: current.muteEntityId == null
                        ? () {}
                        : () => context.read<HomeBloc>().add(
                              ToggleEntity(
                                entityId: current.muteEntityId!,
                              ),
                            ),
                    onOpenApp: current.openAppEntityId == null
                        ? (_) {}
                        : (String package) => context.read<HomeBloc>().add(
                              PressNotifyAction(
                                entityId: current.openAppEntityId!,
                                message: ProjectorSummary.openAppMessage(
                                  package,
                                ),
                              ),
                            ),
                    onButtonPressed: (String entityId) =>
                        context.read<HomeBloc>().add(
                              PressEntityButton(entityId: entityId),
                            ),
                    onOpenRemote: !current.hasRemote
                        ? null
                        : () => showModalBottomSheet<void>(
                              context: context,
                              isScrollControlled: true,
                              useSafeArea: true,
                              constraints:
                                  const BoxConstraints(maxWidth: 1100),
                              builder: (BuildContext sheetContext) =>
                                  FractionallySizedBox(
                                heightFactor: 0.92,
                                child: ProjectorRemoteSheet(
                                  isOn: current.isOn,
                                  onPower: () {
                                    if (powerId == null) return;
                                    context.read<HomeBloc>().add(
                                          PressEntityButton(
                                            entityId: powerId,
                                          ),
                                        );
                                  },
                                  onKey: (int key) =>
                                      context.read<HomeBloc>().add(
                                            PressNotifyAction(
                                              entityId: current
                                                  .pressButtonEntityId!,
                                              message: '[$key]',
                                            ),
                                          ),
                                ),
                              ),
                            ),
                  );
                }

                if (showFanPanel && index == 0) {
                  final FanSummary current = fan;
                  final HaEntityStateModel? master =
                      current.masterSwitch;
                  return Column(
                    children: <Widget>[
                      if (master != null) ...<Widget>[
                        FanLightMasterRow(
                          name: current.name,
                          master: master,
                          isToggling: state.togglingIds
                              .contains(master.entityId),
                          onToggle: () => context.read<HomeBloc>().add(
                                ToggleEntity(entityId: master.entityId),
                              ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      FanControlPanel(
                        summary: current,
                        isToggling: state.togglingIds
                            .contains(current.entity.entityId),
                        onToggle: () => context.read<HomeBloc>().add(
                              ToggleEntity(
                                entityId: current.entity.entityId,
                              ),
                            ),
                        onModeSelected: (String mode) =>
                            context.read<HomeBloc>().add(SetFanPresetMode(
                                  entityId: current.entity.entityId,
                                  mode: mode,
                                )),
                        onSpeedSelected: (int level) =>
                            context.read<HomeBloc>().add(SetFanPercentage(
                                  entityId: current.entity.entityId,
                                  percentage:
                                      FanSummary.percentageForLevel(level),
                                )),
                        onPercentageChanged: (int percentage) =>
                            context.read<HomeBloc>().add(SetFanPercentage(
                                  entityId: current.entity.entityId,
                                  percentage: percentage,
                                )),
                        onOscillatingChanged: (bool oscillating) =>
                            context.read<HomeBloc>().add(SetFanOscillating(
                                  entityId: current.entity.entityId,
                                  oscillating: oscillating,
                                )),
                        onDelayChanged: current.delayEntityId == null
                            ? (_) {}
                            : (int minutes) => context
                                .read<HomeBloc>()
                                .add(SetNumberEntityValue(
                                  entityId: current.delayEntityId!,
                                  value: minutes.toDouble(),
                                )),
                      ),
                    ],
                  );
                }

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
                  return Column(
                    children: <Widget>[
                      ClimateControlPanel(
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
                      ),
                      if (devicePower != null) ...<Widget>[
                        const SizedBox(height: 12),
                        PowerStatsCard(stats: devicePower),
                      ],
                    ],
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
