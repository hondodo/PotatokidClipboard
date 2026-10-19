import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:potatokid_screen/core/utils/platform_channel_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel('potatokid/volume');
  final List<String> methodCalls = <String>[];
  Object? modelReturn = 'TEST-MODEL';
  bool modelThrow = false;

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
    methodCalls.add(call.method);
    if (call.method == 'getDeviceModel') {
      if (modelThrow) {
        throw PlatformException(code: 'unavailable');
      }
      return modelReturn;
    }
    return null;
  });

  setUp(methodCalls.clear);

  test('volumeUp 调用 volumeUp method', () async {
    await PlatformChannelService.instance.volumeUp();
    expect(methodCalls, <String>['volumeUp']);
  });

  test('volumeDown 调用 volumeDown method', () async {
    await PlatformChannelService.instance.volumeDown();
    expect(methodCalls, <String>['volumeDown']);
  });

  test('toggleMute 调用 toggleMute method', () async {
    await PlatformChannelService.instance.toggleMute();
    expect(methodCalls, <String>['toggleMute']);
  });

  test('deviceModel 返回平台值', () async {
    modelReturn = 'TEST-MODEL';
    final String model = await PlatformChannelService.instance.deviceModel();
    expect(methodCalls, <String>['getDeviceModel']);
    expect(model, 'TEST-MODEL');
  });

  test('deviceModel 平台返回空串时回落 Android TV', () async {
    modelReturn = '';
    final String model = await PlatformChannelService.instance.deviceModel();
    expect(model, 'Android TV');
  });

  test('deviceModel 平台异常时回落 Android TV', () async {
    modelThrow = true;
    final String model = await PlatformChannelService.instance.deviceModel();
    expect(model, 'Android TV');
    modelThrow = false;
  });

  test('音量方法平台异常时不抛出', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      throw PlatformException(code: 'boom');
    });
    await expectLater(PlatformChannelService.instance.volumeUp(), completes);
    await expectLater(PlatformChannelService.instance.volumeDown(), completes);
    await expectLater(PlatformChannelService.instance.toggleMute(), completes);
    // 还原正常 handler。
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      methodCalls.add(call.method);
      if (call.method == 'getDeviceModel') {
        return modelReturn;
      }
      return null;
    });
  });
}
