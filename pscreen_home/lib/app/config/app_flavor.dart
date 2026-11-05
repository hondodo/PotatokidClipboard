/// 编译期产品变体，与 `android/app/build.gradle.kts` 的 productFlavors 对应。
///
/// 构建时通过 `--dart-define=APP_FLAVOR=phone|board|parent` 注入；缺省为
/// `board`，保证不带参数时的行为与现有中控端一致。
enum AppFlavor { phone, board, parent }

abstract final class AppFlavorConfig {
  /// 由 `--dart-define` 写入的原始值。
  static const String raw = String.fromEnvironment(
    'APP_FLAVOR',
    defaultValue: 'board',
  );

  static AppFlavor get flavor => switch (raw) {
    'phone' => AppFlavor.phone,
    'parent' => AppFlavor.parent,
    _ => AppFlavor.board,
  };

  /// `parent` 变体只提供家长端能力，不接入中控功能。
  static bool get isParentOnly => flavor == AppFlavor.parent;

  /// 是否作为系统桌面（HOME/DEFAULT）运行；仅 board 的 manifest 注册 HOME。
  static bool get isHomeLauncher => flavor == AppFlavor.board;

  /// 实时通道上报的设备类型：家长端为 `parent`，其余为中控屏 `home`。
  static String get deviceKind => isParentOnly ? 'parent' : 'home';

  /// 实时通道上报的设备名（遥控列表里显示）。
  static String get deviceName => isParentOnly ? '家长端' : '中控台';

  /// App 更新查询用的 appId（yuntu 上按 flavor 维度建的应用）。
  /// 集中在此处，新增 flavor 时只改这里。
  static String get updateAppId => switch (flavor) {
    AppFlavor.phone => 'potatokid-home-phone',
    AppFlavor.parent => 'potatokid-home-parent',
    AppFlavor.board => 'potatokid-home-board',
  };
}
