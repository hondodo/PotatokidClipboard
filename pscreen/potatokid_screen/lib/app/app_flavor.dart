/// 编译期产品变体，与 `android/app/build.gradle.kts` 的 productFlavors 对应。
///
/// 构建时通过 `--dart-define=APP_FLAVOR=phone|tv|board` 注入；缺省为 `tv`，
/// 保证不带参数时的行为与现有电视端一致。
enum AppFlavor { phone, tv, board }

abstract final class AppFlavorConfig {
  /// 由 `--dart-define` 写入的原始值。
  static const String raw = String.fromEnvironment(
    'APP_FLAVOR',
    defaultValue: 'tv',
  );

  static AppFlavor get flavor => switch (raw) {
    'phone' => AppFlavor.phone,
    'board' => AppFlavor.board,
    _ => AppFlavor.tv,
  };

  /// 是否作为系统桌面（HOME/DEFAULT）运行；仅 board 的 manifest 注册 HOME。
  static bool get isHomeLauncher => flavor == AppFlavor.board;

  /// App 更新查询用的 appId（yuntu 上按 flavor 维度建的应用）。
  /// 集中在此处，新增 flavor 时只改这里。
  static String get updateAppId => switch (flavor) {
    AppFlavor.tv => 'potatokid-screen-tv',
    AppFlavor.phone => 'potatokid-screen-phone',
    AppFlavor.board => 'potatokid-screen-board',
  };
}
