import 'package:flutter_test/flutter_test.dart';
import 'package:potatokid_screen/core/utils/app_settings.dart';
import 'package:potatokid_screen/core/utils/wordpress_util.dart';

const String _testUrl = 'https://potatokid5.wordpress.com/2026/10/19/hello/';
const String _testPassword = '12345678';

void main() {
  setUp(() async {
    await AppSettings.instance.clearAllPersisted();
  });

  test('正确密码返回非空正文且不含密码表单标记', () async {
    final String content = await WordPressUtil.fetchPostContent(
      _testUrl,
      password: _testPassword,
    );
    expect(content, isNotEmpty);
    expect(content, isNot(contains('post-password-form')));
  });

  test('错误密码抛 WordPressPassException', () async {
    await expectLater(
      WordPressUtil.fetchPostContent(_testUrl, password: 'wrong-password-xyz'),
      throwsA(isA<WordPressPassException>()),
    );
  });

  test('空密码且 AppSettings 未设置密码时抛 WordPressPassException', () async {
    await expectLater(
      WordPressUtil.fetchPostContent(_testUrl),
      throwsA(isA<WordPressPassException>()),
    );
  });

  test('password 参数缺省时从 AppSettings 读取', () async {
    await AppSettings.instance.setWpPassword(_testPassword);
    final String content = await WordPressUtil.fetchPostContent(_testUrl);
    expect(content, isNotEmpty);
    expect(content, isNot(contains('post-password-form')));
  });
}
