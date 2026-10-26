import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_screen/core/utils/device_identity.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final RegExp dashed = RegExp(r'^[0-9a-f]{4}(-[0-9a-f]{4}){3}$');

  group('DeviceIdentity.normalize', () {
    test('16 位十六进制直接分组', () {
      expect(DeviceIdentity.normalize('abcdef0123456789'), 'abcd-ef01-2345-6789');
    });

    test('大写十六进制归一为小写', () {
      expect(DeviceIdentity.normalize('ABCDEF0123456789'), 'abcd-ef01-2345-6789');
    });

    test('首尾空白被忽略', () {
      expect(DeviceIdentity.normalize('  abcdef0123456789  '), 'abcd-ef01-2345-6789');
    });

    test('非 16 位值用 MD5 收敛为固定格式且稳定', () {
      final String first = DeviceIdentity.normalize('deadbeef');
      final String second = DeviceIdentity.normalize('deadbeef');
      expect(first, matches(dashed));
      expect(first, second);
    });

    test('空串返回空串', () {
      expect(DeviceIdentity.normalize(''), '');
      expect(DeviceIdentity.normalize('   '), '');
    });

    test('全零视为无效', () {
      expect(DeviceIdentity.normalize('0000000000000000'), '');
    });

    test('Android 2.2 已知错误值视为无效', () {
      expect(DeviceIdentity.normalize('9774d56d682e549c'), '');
      expect(DeviceIdentity.normalize('9774D56D682E549C'), '');
    });

    test('非十六进制字符走 MD5 分支', () {
      expect(DeviceIdentity.normalize('device-01'), matches(dashed));
    });
  });

  group('DeviceIdentity.resolve', () {
    const MethodChannel channel = MethodChannel('potatokid/volume');

    test('优先取 ANDROID_ID 并格式化为四组', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getDeviceIdentity') {
          return <String, String>{
            'androidId': 'abcdef0123456789',
            'mediaDrmId': '00112233445566778899aabbccddeeff',
          };
        }
        return null;
      });

      expect(await DeviceIdentity.instance.resolve(), 'abcd-ef01-2345-6789');
    });
  });
}
