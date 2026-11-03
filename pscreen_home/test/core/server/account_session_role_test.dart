import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/core/router/route_names.dart';
import 'package:pscreen_home/core/server/account_session.dart';

void main() {
  group('AccountSession 三级角色首页分流', () {
    test('parent 登录后直落家长视图', () {
      expect(
        AccountSession.initialHomePathFor('parent'),
        RouteNames.parentalPath,
      );
      expect(RouteNames.parentalPath, '/parental');
    });

    test('admin / user 保持现有中控台首页', () {
      expect(AccountSession.initialHomePathFor('admin'), RouteNames.home);
      expect(AccountSession.initialHomePathFor('user'), RouteNames.home);
    });

    test('未登录或未知角色按 user 保守处理', () {
      expect(AccountSession.initialHomePathFor(''), RouteNames.home);
      expect(AccountSession.initialHomePathFor('root'), RouteNames.home);
    });
  });
}
