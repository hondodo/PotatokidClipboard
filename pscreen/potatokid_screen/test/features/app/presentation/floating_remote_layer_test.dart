import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:potatokid_screen/features/app/application/bloc/app_bloc.dart';
import 'package:potatokid_screen/features/app/application/bloc/app_event.dart';
import 'package:potatokid_screen/shared/widgets/floating_remote.dart';
import 'package:pscreen_screen/core/utils/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 复刻 `App.builder` 的层级：Navigator 与 [FloatingRemote] 同处一个 Stack，
/// 遥控器后绘制，因此位于所有 DialogRoute 之上。
///
/// 回归目标：退出确认之类的 `showDialog` 弹窗不能再遮住模拟遥控，也不能让
/// ModalBarrier 吞掉它的点击。
void main() {
  testWidgets('DialogRoute 弹出后模拟遥控仍可见且可点击', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // 预热，避免 AppBloc 的异步持久化加载在后面覆盖显隐开关。
    await AppSettings.instance.ensureLoaded();
    final AppBloc bloc = AppBloc();
    final List<RemoteButton> pressed = <RemoteButton>[];

    await tester.pumpWidget(
      BlocProvider<AppBloc>.value(
        value: bloc,
        child: MaterialApp(
          builder: (BuildContext context, Widget? child) => Stack(
            fit: StackFit.expand,
            children: <Widget>[
              child ?? const SizedBox.shrink(),
              FloatingRemote(onKey: pressed.add),
            ],
          ),
          home: const Scaffold(body: Center(child: Text('页面'))),
        ),
      ),
    );
    await tester.pumpAndSettle();
    bloc.add(const SetFloatingRemote(true));
    await tester.pumpAndSettle();
    expect(find.text('OK'), findsOneWidget, reason: '模拟遥控已开启');

    final BuildContext pageContext = tester.element(find.text('页面'));
    unawaited(
      showDialog<void>(
        context: pageContext,
        barrierDismissible: false,
        builder: (_) => const AlertDialog(title: Text('退出应用')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('退出应用'), findsOneWidget);
    expect(find.text('OK'), findsOneWidget, reason: '弹窗期间遥控器仍在树上');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(
      pressed,
      <RemoteButton>[RemoteButton.ok],
      reason: '遥控器在 barrier 之上，点击命中 OK 而不是被遮罩吞掉',
    );
  });
}
