import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_screen/core/utils/desktop_device_model.dart';
import 'package:pscreen_screen/core/utils/desktop_device_model_format.dart';
import 'package:pscreen_screen/features/remote/data/repositories/remote_login_repository_impl.dart';

void main() {
  group('formatDesktopModel', () {
    test('厂商 + 产品名拼接成机型', () {
      expect(
        formatDesktopModel(
          manufacturer: 'Dell Inc.',
          product: 'OptiPlex 7080',
        ),
        'Dell Inc. OptiPlex 7080',
      );
    });

    test('产品名已包含厂商时不重复拼接', () {
      expect(
        formatDesktopModel(
          manufacturer: 'Dell Inc.',
          product: 'Dell Inc. OptiPlex 7080',
        ),
        'Dell Inc. OptiPlex 7080',
      );
    });

    test('只有厂商时直接用厂商', () {
      expect(
        formatDesktopModel(manufacturer: 'LENOVO', product: null),
        'LENOVO',
      );
    });

    test('BIOS 占位值视为无效，回落系统名称', () {
      expect(
        formatDesktopModel(
          manufacturer: 'To be filled by O.E.M.',
          product: 'Default string',
          osName: 'Ubuntu 22.04.3 LTS',
        ),
        'Ubuntu 22.04.3 LTS',
      );
    });

    test('系统名称也无效时用 fallback', () {
      expect(
        formatDesktopModel(
          product: 'System Product Name',
          osName: 'Unknown',
          fallback: 'Windows 10 Pro 19045',
        ),
        'Windows 10 Pro 19045',
      );
    });

    test('全部为空返回空串（服务端保留既有值）', () {
      expect(formatDesktopModel(), '');
    });

    test('超长型号截断到服务端上限 64', () {
      final String result = formatDesktopModel(product: 'M' * 100);
      expect(result.length, kDeviceModelMaxLength);
    });

    test('多余空白归一化', () {
      expect(
        formatDesktopModel(manufacturer: '  HP  ', product: '  EliteDesk\n800  '),
        'HP EliteDesk 800',
      );
    });
  });

  group('cleanDesktopModelValue', () {
    test('空值与占位值返回 null', () {
      expect(cleanDesktopModelValue(null), isNull);
      expect(cleanDesktopModelValue('   '), isNull);
      expect(cleanDesktopModelValue('To be filled by O.E.M.'), isNull);
      expect(cleanDesktopModelValue('Default string'), isNull);
      expect(cleanDesktopModelValue('N/A'), isNull);
    });

    test('正常值保留', () {
      expect(cleanDesktopModelValue(' rk3288 '), 'rk3288');
    });
  });

  group('桌面真机采集', () {
    test('desktopDeviceModel 不抛异常、长度受限、不含假型号', () async {
      final String model = await desktopDeviceModel();
      // 便于人工核对本机真实机型（Windows BIOS / Linux DMI）。
      // ignore: avoid_print
      print('[desktopDeviceModel] 本机采集结果: "$model"');
      expect(model.length, lessThanOrEqualTo(kDeviceModelMaxLength));
      expect(model.contains('Android TV'), isFalse);
    });

    test('桌面平台不走 Android TV 假型号兜底', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final String model =
          await RemoteLoginRepositoryImpl.defaultDeviceModel();
      expect(model, isNot('Android TV'));
      expect(model.length, lessThanOrEqualTo(kDeviceModelMaxLength));
    });
  });
}
