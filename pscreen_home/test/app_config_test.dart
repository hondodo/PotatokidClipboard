import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/app/config/app_config.dart';

void main() {
  setUp(() {
    // 模拟 .env 默认值（测试环境不加载 dotenv）
    AppConfig.envHost = 'http://localhost:8123';
    AppConfig.envToken = 'env_token';
    AppConfig.applyOverrides();
  });

  tearDown(() {
    AppConfig.applyOverrides();
    AppConfig.envHost = 'http://localhost:8123';
    AppConfig.envToken = '';
  });

  group('AppConfig 生效值优先级', () {
    test('无持久化覆盖时使用 .env 默认值', () {
      expect(AppConfig.haHost, 'http://localhost:8123');
      expect(AppConfig.haToken, 'env_token');
      expect(AppConfig.hasHostOverride, isFalse);
      expect(AppConfig.hasTokenOverride, isFalse);
      expect(AppConfig.isConfigured, isTrue);
    });

    test('有覆盖时持久化值优先于 .env', () {
      AppConfig.applyOverrides(host: '192.168.1.10:8123', token: 'my_token');

      expect(AppConfig.haHost, '192.168.1.10:8123');
      expect(AppConfig.haToken, 'my_token');
      expect(AppConfig.hasHostOverride, isTrue);
      expect(AppConfig.hasTokenOverride, isTrue);
      expect(AppConfig.envHost, 'http://localhost:8123',
          reason: '.env 默认值不应被覆盖污染');
    });

    test('覆盖清空（空串）后回落 .env', () {
      AppConfig.applyOverrides(host: '10.0.0.2:8123', token: 'x');
      expect(AppConfig.haHost, '10.0.0.2:8123');

      AppConfig.applyOverrides(host: '', token: '');
      expect(AppConfig.haHost, 'http://localhost:8123');
      expect(AppConfig.haToken, 'env_token');
      expect(AppConfig.hasHostOverride, isFalse);
      expect(AppConfig.hasTokenOverride, isFalse);
    });

    test('覆盖值两端空白被裁剪', () {
      AppConfig.applyOverrides(host: '  10.0.0.2:8123  ', token: ' tok ');
      expect(AppConfig.haHost, '10.0.0.2:8123');
      expect(AppConfig.haToken, 'tok');
    });
  });

  group('AppConfig.haWsUrl', () {
    test('http → ws，并去掉尾部斜杠', () {
      AppConfig.applyOverrides(host: 'http://home.local:8123/');
      expect(AppConfig.haWsUrl, 'ws://home.local:8123/api/websocket');
    });

    test('https → wss', () {
      AppConfig.applyOverrides(host: 'https://ha.example.com');
      expect(AppConfig.haWsUrl, 'wss://ha.example.com/api/websocket');
    });

    test('裸地址补 ws://；覆盖变化后地址随之变化', () {
      AppConfig.applyOverrides(host: '192.168.1.10:8123');
      expect(AppConfig.haWsUrl, 'ws://192.168.1.10:8123/api/websocket');

      // 清空回落 .env（localhost）
      AppConfig.applyOverrides();
      expect(AppConfig.haWsUrl, 'ws://localhost:8123/api/websocket');
    });
  });
}
