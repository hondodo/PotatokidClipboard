import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';

/// 投影仪摘要：坚果投影仪在 HA 里没有 media_player / 电源 switch，
/// 而是拆成开机 / 关机 button、音量 / 亮度 number、输入源 select、
/// 应用列表 sensor、打开应用 notify 等实体。
///
/// 开关机状态用 devicestartup / deviceshutdown 事件时间推断。
class ProjectorSummary {
  const ProjectorSummary({
    required this.deviceId,
    required this.name,
    required this.isOn,
    required this.volume,
    required this.brightness,
    required this.mute,
    required this.inputs,
    required this.apps,
    this.volumeMin = 0,
    this.volumeMax = 100,
    this.brightnessMin = 1,
    this.brightnessMax = 10,
    this.volumeEntityId,
    this.brightnessEntityId,
    this.inputEntityId,
    this.muteEntityId,
    this.input,
    this.currentAppPackage,
    this.currentAppName,
    this.openAppEntityId,
    this.appListEntityId,
    this.appPackageEntityId,
    this.powerOnEntityId,
    this.powerOffEntityId,
    this.powerOnAvailable = false,
    this.powerOffAvailable = false,
    this.playEntityId,
    this.pauseEntityId,
    this.nextEntityId,
    this.previousEntityId,
    this.stopEntityId,
  });

  static ProjectorSummary? tryBuild({
    required String deviceId,
    required String name,
    required Iterable<HaEntityStateModel> entities,
  }) {
    final HaEntityStateModel? appList =
        _byId(entities, '_applist_p_8_2', domain: 'sensor');
    final HaEntityStateModel? brightness =
        _byId(entities, '_brightness_p_2_3', domain: 'number');
    if (appList == null || brightness == null) return null;

    final HaEntityStateModel? volume =
        _byId(entities, '_volume_p_4_1', domain: 'number');
    final HaEntityStateModel? input =
        _byId(entities, '_input_control_p_2_2', domain: 'select');
    final HaEntityStateModel? mute =
        _byId(entities, '_mute_p_4_2', domain: 'switch');
    final HaEntityStateModel? powerOn =
        _byId(entities, '_turn_on_a_7_1', domain: 'button');
    final HaEntityStateModel? powerOff =
        _byId(entities, '_turn_off_a_2_1', domain: 'button');
    final HaEntityStateModel? startup =
        _byId(entities, '_devicestartup_e_8_2', domain: 'event');
    final HaEntityStateModel? shutdown =
        _byId(entities, '_deviceshutdown_e_8_1', domain: 'event');
    final HaEntityStateModel? package =
        _byId(entities, '_apppackagename_p_8_1', domain: 'text');
    final HaEntityStateModel? openApp =
        _byId(entities, '_openapp_a_8_1', domain: 'notify');

    final List<ProjectorApp> apps = _parseApps(appList.state);
    final String? currentPackage = package?.state;
    String? currentApp;
    if (currentPackage != null) {
      for (final ProjectorApp app in apps) {
        if (app.package == currentPackage) {
          currentApp = app.name;
          break;
        }
      }
    }

    return ProjectorSummary(
      deviceId: deviceId,
      name: name,
      isOn: _inferPower(startup?.state, shutdown?.state),
      volume: _int(volume?.state) ?? 0,
      brightness: _int(brightness.state) ?? 1,
      mute: mute?.isOn ?? false,
      inputs: input?.options ?? const <String>[],
      apps: apps,
      volumeMin: _int(volume?.attributes['min']) ?? 0,
      volumeMax: _int(volume?.attributes['max']) ?? 100,
      brightnessMin: _int(brightness.attributes['min']) ?? 1,
      brightnessMax: _int(brightness.attributes['max']) ?? 10,
      volumeEntityId: volume?.entityId,
      brightnessEntityId: brightness.entityId,
      inputEntityId: input?.entityId,
      muteEntityId: mute?.entityId,
      input: input?.state,
      currentAppPackage: currentPackage,
      currentAppName: currentApp,
      openAppEntityId: openApp?.entityId,
      appListEntityId: appList.entityId,
      appPackageEntityId: package?.entityId,
      powerOnEntityId: powerOn?.entityId,
      powerOffEntityId: powerOff?.entityId,
      powerOnAvailable: _buttonAvailable(powerOn),
      powerOffAvailable: _buttonAvailable(powerOff),
      playEntityId: _byId(entities, '_play_a_3_3', domain: 'button')?.entityId,
      pauseEntityId: _byId(entities, '_pause_a_3_4', domain: 'button')?.entityId,
      nextEntityId: _byId(entities, '_next_a_3_5', domain: 'button')?.entityId,
      previousEntityId:
          _byId(entities, '_previous_a_3_6', domain: 'button')?.entityId,
      stopEntityId: _byId(entities, '_stop_a_3_7', domain: 'button')?.entityId,
    );
  }

  final String deviceId;
  final String name;
  final bool isOn;
  final int volume;
  final int brightness;
  final bool mute;
  final List<String> inputs;
  final List<ProjectorApp> apps;
  final int volumeMin;
  final int volumeMax;
  final int brightnessMin;
  final int brightnessMax;
  final String? volumeEntityId;
  final String? brightnessEntityId;
  final String? inputEntityId;
  final String? muteEntityId;
  final String? input;
  final String? currentAppPackage;
  final String? currentAppName;
  final String? openAppEntityId;
  final String? appListEntityId;
  final String? appPackageEntityId;
  final String? powerOnEntityId;
  final String? powerOffEntityId;
  final bool powerOnAvailable;
  final bool powerOffAvailable;
  final String? playEntityId;
  final String? pauseEntityId;
  final String? nextEntityId;
  final String? previousEntityId;
  final String? stopEntityId;

  String get title => isOn ? '已开启' : '已关闭';

  String get statusLabel {
    if (!isOn) return '已关闭';
    final String source = currentAppName ?? currentAppPackage ?? input ?? '已开启';
    return source;
  }

  String get volumeLabel => '$volume%';

  String get brightnessLabel => '$brightness';

  String get powerLabel => isOn ? '关机' : '开机';

  bool get hasPlayback =>
      playEntityId != null ||
      pauseEntityId != null ||
      nextEntityId != null ||
      previousEntityId != null ||
      stopEntityId != null;

  /// 打开应用的 notify 参数（集成按 YAML 列表解析）
  static String openAppMessage(String package) => '[$package]';

  static List<ProjectorApp> _parseApps(String raw) {
    final RegExp pattern = RegExp(r'"name":"([^"]+)","pkg":"([^"]+)"');
    final List<ProjectorApp> result = <ProjectorApp>[];
    for (final RegExpMatch match in pattern.allMatches(raw)) {
      final String? name = match.group(1);
      final String? package = match.group(2);
      if (name == null || package == null) continue;
      result.add(ProjectorApp(name: name, package: package));
    }
    return result;
  }

  static bool _inferPower(String? startup, String? shutdown) {
    final DateTime? on = DateTime.tryParse(startup ?? '');
    final DateTime? off = DateTime.tryParse(shutdown ?? '');
    if (on == null) return false;
    if (off == null) return true;
    return on.isAfter(off);
  }

  static bool _buttonAvailable(HaEntityStateModel? entity) {
    if (entity == null) return false;
    return entity.state != 'unavailable';
  }

  static HaEntityStateModel? _byId(
    Iterable<HaEntityStateModel> entities,
    String part, {
    required String domain,
  }) {
    for (final HaEntityStateModel entity in entities) {
      if (entity.domain != domain) continue;
      if (entity.entityId.contains(part)) return entity;
    }
    return null;
  }

  static int? _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}

class ProjectorApp {
  const ProjectorApp({required this.name, required this.package});

  final String name;
  final String package;
}
