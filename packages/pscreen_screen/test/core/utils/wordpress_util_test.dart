import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_screen/core/utils/app_settings.dart';
import 'package:pscreen_screen/core/utils/wordpress_util.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 假 WordPress 站点域名（`.test` 是保留域，永远解析不到真实主机）。
const String _testHost = 'wordpress.test';

/// 受密码保护的文章地址。
const String _testUrl = 'http://$_testHost/2026/10/19/hello/';

const String _testPassword = '12345678';

/// 本地假 WordPress 站点：模拟「密码保护文章 + wp-login.php 校验」这套流程。
///
/// 原测试直接请求线上 `potatokid5.wordpress.com`，而那个博客已被删除
/// （整站返回 HTTP 410），线上依赖会让测试必然失败。这里改成在本地起一个
/// [HttpServer]，再把 [_testHost] 的请求代理到它——被测代码走的是完全相同的
/// HTTP 流程，但测试完全离线、可重复。
class _FakeWordPress {
  _FakeWordPress._(this._server);

  static Future<_FakeWordPress> start() async {
    final HttpServer server =
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final _FakeWordPress fake = _FakeWordPress._(server);
    server.listen((HttpRequest request) => fake._handle(request));
    return fake;
  }

  final HttpServer _server;

  int get port => _server.port;

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    if (request.method == 'POST' && request.uri.path == '/wp-login.php') {
      await _handleLogin(request);
      return;
    }
    if (request.method == 'GET' && request.uri.path == '/2026/10/19/hello/') {
      await _handlePost(request);
      return;
    }
    request.response.statusCode = HttpStatus.notFound;
    await request.response.close();
  }

  /// `wp-login.php?action=postpass`：校验密码并下发 wp-postpass cookie。
  Future<void> _handleLogin(HttpRequest request) async {
    final String body = await utf8.decoder.bind(request).join();
    final String password = Uri.splitQueryString(body)['post_password'] ?? '';
    request.response.statusCode = HttpStatus.found;
    request.response.headers
      ..set(HttpHeaders.locationHeader, '/2026/10/19/hello/')
      ..add('Set-Cookie', 'wp-postpass_test=$password; Path=/');
    await request.response.close();
  }

  /// 文章页：带正确的 wp-postpass cookie 才给正文，否则给密码表单。
  Future<void> _handlePost(HttpRequest request) async {
    final String? cookie = request.headers.value(HttpHeaders.cookieHeader);
    request.response.headers.contentType = ContentType.html;
    if (cookie != null && cookie.contains('wp-postpass_test=$_testPassword')) {
      request.response.write(_unlockedHtml);
    } else {
      request.response.write(_lockedHtml);
    }
    await request.response.close();
  }
}

/// 把 [_testHost] 的请求代理到本地假站点；其它域名一律直连。
///
/// 刻意继承 [HttpOverrides] 而不是用 `HttpOverrides.runZoned` 的回调参数：
/// `createHttpClient` 若写成 `HttpClient(context: context)`，工厂会回头调用
/// `HttpOverrides.current.createHttpClient`，直接 new 会无限递归；这里沿用基类
/// 实现（底层真实客户端）即可，只覆盖代理解析。
class _FakeSiteOverrides extends HttpOverrides {
  _FakeSiteOverrides(this.port);

  final int port;

  @override
  String findProxyFromEnvironment(
    Uri url,
    Map<String, String>? environment,
  ) =>
      url.host == _testHost ? 'PROXY 127.0.0.1:$port' : 'DIRECT';
}

/// 未解锁：只有密码表单，没有正文。
const String _lockedHtml = '''
<!DOCTYPE html>
<html>
<body>
<form class="post-password-form" action="/wp-login.php?action=postpass" method="post">
  <input name="post_password" type="password" />
  <input type="submit" value="确定" />
</form>
</body>
</html>
''';

/// 已解锁：正文在 entry-content 里，且不再有密码表单。
const String _unlockedHtml = '''
<!DOCTYPE html>
<html>
<body>
<div class="entry-content">
<p>正文内容</p>
</div>
</body>
</html>
''';

void main() {
  late _FakeWordPress fake;

  /// 在假站点代理下跑一段测试体。
  ///
  /// 这里显式装一套 [HttpOverrides]：flutter_test 会把全局 [HttpOverrides] 换成
  /// 「所有请求都返回 400」的假客户端（见 flutter_test 的 setupHttpOverrides），
  /// 不覆盖掉它就没法发真实请求。
  Future<void> withFakeSite(Future<void> Function() body) {
    return HttpOverrides.runWithHttpOverrides<Future<void>>(
      body,
      _FakeSiteOverrides(fake.port),
    );
  }

  setUp(() async {
    fake = await _FakeWordPress.start();
    // 密码持久化走 SharedPreferences：显式给一份空的 mock，不依赖宿主环境。
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await AppSettings.instance.clearAllPersisted();
  });

  tearDown(() async {
    await fake.close();
  });

  test('正确密码返回非空正文且不含密码表单标记', () async {
    await withFakeSite(() async {
      final String content = await WordPressUtil.fetchPostContent(
        _testUrl,
        password: _testPassword,
      );
      expect(content, isNotEmpty);
      expect(content, isNot(contains('post-password-form')));
    });
  });

  test('错误密码抛 WordPressPassException', () async {
    await withFakeSite(() async {
      await expectLater(
        WordPressUtil.fetchPostContent(_testUrl, password: 'wrong-password-xyz'),
        throwsA(isA<WordPressPassException>()),
      );
    });
  });

  test('空密码且 AppSettings 未设置密码时抛 WordPressPassException', () async {
    await withFakeSite(() async {
      await expectLater(
        WordPressUtil.fetchPostContent(_testUrl),
        throwsA(isA<WordPressPassException>()),
      );
    });
  });

  test('password 参数缺省时从 AppSettings 读取', () async {
    await withFakeSite(() async {
      await AppSettings.instance.setWpPassword(_testPassword);
      final String content = await WordPressUtil.fetchPostContent(_testUrl);
      expect(content, isNotEmpty);
      expect(content, isNot(contains('post-password-form')));
    });
  });
}
