import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/app/config/ha_config.dart';

void main() {
  setUp(() {
    // 模拟 .env 默认值（测试环境不加载 dotenv）
    HaConfig.envHost = 'http://localhost:8123';
    HaConfig.envToken = 'env_token';
    HaConfig.envHomeName = '';
    HaConfig.applyOverrides();
  });

  tearDown(() {
    HaConfig.applyOverrides();
    HaConfig.envHost = 'http://localhost:8123';
    HaConfig.envToken = '';
    HaConfig.envHomeName = '';
  });

  group('HaConfig 生效值优先级', () {
    test('无持久化覆盖时使用 .env 默认值', () {
      expect(HaConfig.haHost, 'http://localhost:8123');
      expect(HaConfig.haToken, 'env_token');
      expect(HaConfig.hasHostOverride, isFalse);
      expect(HaConfig.hasTokenOverride, isFalse);
      expect(HaConfig.isConfigured, isTrue);
    });

    test('有覆盖时持久化值优先于 .env', () {
      HaConfig.applyOverrides(host: '192.168.1.10:8123', token: 'my_token');

      expect(HaConfig.haHost, '192.168.1.10:8123');
      expect(HaConfig.haToken, 'my_token');
      expect(HaConfig.hasHostOverride, isTrue);
      expect(HaConfig.hasTokenOverride, isTrue);
      expect(HaConfig.envHost, 'http://localhost:8123',
          reason: '.env 默认值不应被覆盖污染');
    });

    test('覆盖清空（空串）后回落 .env', () {
      HaConfig.applyOverrides(host: '10.0.0.2:8123', token: 'x');
      expect(HaConfig.haHost, '10.0.0.2:8123');

      HaConfig.applyOverrides(host: '', token: '');
      expect(HaConfig.haHost, 'http://localhost:8123');
      expect(HaConfig.haToken, 'env_token');
      expect(HaConfig.hasHostOverride, isFalse);
      expect(HaConfig.hasTokenOverride, isFalse);
    });

    test('覆盖值两端空白被裁剪', () {
      HaConfig.applyOverrides(host: '  10.0.0.2:8123  ', token: ' tok ');
      expect(HaConfig.haHost, '10.0.0.2:8123');
      expect(HaConfig.haToken, 'tok');
    });
  });

  group('HaConfig.pinnedHomeName', () {
    test('留空表示不限制（显示全部家庭）', () {
      HaConfig.envHomeName = '';
      expect(HaConfig.pinnedHomeName, '');
    });

    test('「全部」表示不限制', () {
      HaConfig.envHomeName = '全部';
      expect(HaConfig.pinnedHomeName, '');

      HaConfig.envHomeName = 'ALL';
      expect(HaConfig.pinnedHomeName, '');
    });

    test('指定家庭名时锁定该家庭，并裁剪两端空白', () {
      HaConfig.envHomeName = '  金科1204  ';
      expect(HaConfig.pinnedHomeName, '金科1204');
    });
  });

  group('HaConfig.haWsUrl', () {
    test('http → ws，并去掉尾部斜杠', () {
      HaConfig.applyOverrides(host: 'http://home.local:8123/');
      expect(HaConfig.haWsUrl, 'ws://home.local:8123/api/websocket');
    });

    test('https → wss', () {
      HaConfig.applyOverrides(host: 'https://ha.example.com');
      expect(HaConfig.haWsUrl, 'wss://ha.example.com/api/websocket');
    });

    test('裸地址补 ws://；覆盖变化后地址随之变化', () {
      HaConfig.applyOverrides(host: '192.168.1.10:8123');
      expect(HaConfig.haWsUrl, 'ws://192.168.1.10:8123/api/websocket');

      // 清空回落 .env（localhost）
      HaConfig.applyOverrides();
      expect(HaConfig.haWsUrl, 'ws://localhost:8123/api/websocket');
    });
  });
}
