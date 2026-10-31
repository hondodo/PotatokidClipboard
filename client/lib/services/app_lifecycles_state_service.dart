import 'dart:async';

import 'package:flutter/widgets.dart';

class AppLifecyclesStateService extends Object {
  static AppLifecycleState currentState = AppLifecycleState.resumed;

  static void onAppLifecycleStateChange(AppLifecycleState state) {
    debugPrint('应用状态变化: $state');
    currentState = state;
    appLifecyclesStateController.add(state);
    debugPrint('应用状态变化广播完成: $state');
  }

  // 应用程序状态变化
  static final StreamController<AppLifecycleState>
      appLifecyclesStateController =
      StreamController<AppLifecycleState>.broadcast();

  // 应用程序状态变化
  static Stream<AppLifecycleState> get appLifecyclesStateStream =>
      appLifecyclesStateController.stream;
}
