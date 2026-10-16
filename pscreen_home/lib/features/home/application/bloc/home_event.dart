import 'dart:async';

import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';

/// 主页状态机事件基类。
abstract class HomeEvent {
  const HomeEvent();
}

/// 加载全部实体状态（连接就绪 / 重连成功后触发）。
class LoadHome extends HomeEvent {
  const LoadHome({this.completer});

  /// 供调用方 await 事件完成。
  final Completer<bool>? completer;
}

/// 收到一条实时实体状态变更（state_changed）。
class EntityStateChanged extends HomeEvent {
  const EntityStateChanged(this.entity);

  final HaEntityStateModel entity;
}

/// 点击快捷控件切换开关（乐观更新，失败回滚）。
class ToggleEntity extends HomeEvent {
  const ToggleEntity({required this.entityId, this.completer});

  final String entityId;

  /// 供调用方 await 事件完成。
  final Completer<bool>? completer;
}

/// 清除错误提示（页面展示 SnackBar 后调用）。
class ClearHomeError extends HomeEvent {
  const ClearHomeError();
}
