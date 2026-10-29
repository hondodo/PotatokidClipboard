import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_screen/core/media/sleep_timer_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final SleepTimerController timer = SleepTimerController.instance;

  tearDown(() {
    timer.onExpire = null;
    timer.setMinutes(null);
  });

  test('宿主注入 onExpire 后，到点执行自定义动作而不是退出应用', () {
    int expired = 0;
    timer.onExpire = () => expired++;

    FakeAsync().run((FakeAsync async) {
      timer.setMinutes(1);
      expect(timer.active, isTrue);

      async.elapse(const Duration(minutes: 1));

      expect(expired, 1);
      expect(timer.active, isFalse);
      expect(timer.remaining, Duration.zero);
    });
  });

  test('未注入 onExpire 时，到点仍调用 SystemNavigator.pop', () {
    int pops = 0;
    final TestDefaultBinaryMessenger messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (
      MethodCall call,
    ) async {
      if (call.method == 'SystemNavigator.pop') pops++;
      return null;
    });

    FakeAsync().run((FakeAsync async) {
      timer.setMinutes(1);
      async.elapse(const Duration(minutes: 1));
      async.flushMicrotasks();

      expect(pops, 1);
      expect(timer.active, isFalse);
    });

    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });
}
