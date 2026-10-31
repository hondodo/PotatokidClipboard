/// 类型安全路由参数基类。
///
/// 每个页面参数类实现 [toMap]，并提供 `factory XxxParams.fromMap(...)`。
/// 通过 GoRouter 的 `state.extra` 传递。
abstract class RouteParams {
  const RouteParams();

  Map<String, dynamic> toMap();
}

/// 首页详情页参数
class HomeDetailParams extends RouteParams {
  const HomeDetailParams({this.id, this.title});

  final String? id;
  final String? title;

  @override
  Map<String, dynamic> toMap() => <String, dynamic>{'id': id, 'title': title};

  factory HomeDetailParams.fromMap(Map<String, dynamic> map) => HomeDetailParams(
        id: map['id'] as String?,
        title: map['title'] as String?,
      );
}

/// 设置弹层参数
class SettingsSheetParams extends RouteParams {
  const SettingsSheetParams({this.from});

  final String? from;

  @override
  Map<String, dynamic> toMap() => <String, dynamic>{'from': from};

  factory SettingsSheetParams.fromMap(Map<String, dynamic> map) =>
      SettingsSheetParams(from: map['from'] as String?);
}
