import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_screen/core/update/app_update_models.dart';

Map<String, dynamic> _payload({
  required bool hasUpdate,
  required bool forceUpdate,
  Map<String, dynamic>? latest,
  Map<String, dynamic>? download,
  int currentBuild = 8,
  String platform = 'apk',
}) =>
    <String, dynamic>{
      'code': 0,
      'msg': 'ok',
      'data': <String, dynamic>{
        'app': 'potatokid-screen',
        'platform': platform,
        'checkedAt': '2026-11-05T04:10:00Z',
        'hasUpdate': hasUpdate,
        'forceUpdate': forceUpdate,
        'current': <String, dynamic>{'version': '1.0.3', 'build': currentBuild},
        'latest': latest,
        'download': download,
      },
    };

Map<String, dynamic> _latest(int build, {String version = '1.0.4', String? externalUrl}) => <String, dynamic>{
      'releaseId': 'rel_$build',
      'version': version,
      'build': build,
      'distribution': externalUrl == null ? 'file' : 'external',
      'fileAvailable': externalUrl == null,
      'externalUrl': externalUrl,
      'forceUpdate': false,
    };

Map<String, dynamic> _download({String sha = 'abc123', int size = 1024}) => <String, dynamic>{
      'url': 'http://127.0.0.1:9999/api/download/rel_9?exp=1800000000&sig=x',
      'size': size,
      'sha256': sha,
      'filename': 'app.apk',
      'expiresAt': '2027-01-01T00:00:00.000Z',
    };

void main() {
  group('更新判定矩阵', () {
    test('落后 + 强更 → 需要更新且强更拦截', () {
      final AppUpdateCheckResult result = AppUpdateCheckResult.fromJson(
        _payload(hasUpdate: true, forceUpdate: true, latest: _latest(9), download: _download()),
        appId: 'potatokid-screen',
        platform: 'apk',
      );
      expect(result.hasUpdate, isTrue);
      expect(result.forceRequired, isTrue);
      expect(result.canSilentlyDownload, isTrue);
      expect(result.latest!.releaseId, 'rel_9');
    });

    test('落后 + 非强更 → 只提示，可忽略', () {
      final AppUpdateCheckResult result = AppUpdateCheckResult.fromJson(
        _payload(hasUpdate: true, forceUpdate: false, latest: _latest(9), download: _download()),
        appId: 'potatokid-screen',
        platform: 'apk',
      );
      expect(result.hasUpdate, isTrue);
      expect(result.forceRequired, isFalse);
      expect(result.canSilentlyDownload, isTrue);
    });

    test('已最新（latest=null）→ 无更新入口', () {
      final AppUpdateCheckResult result = AppUpdateCheckResult.fromJson(
        _payload(hasUpdate: false, forceUpdate: false),
        appId: 'potatokid-screen',
        platform: 'apk',
      );
      expect(result.hasUpdate, isFalse);
      expect(result.showPillLike(), isFalse);
      expect(result.latest, isNull);
    });

    test('客户端领先（服务端 hasUpdate=false）→ 不降级、不提示', () {
      final AppUpdateCheckResult result = AppUpdateCheckResult.fromJson(
        _payload(hasUpdate: false, forceUpdate: false, currentBuild: 12, latest: _latest(9)),
        appId: 'potatokid-screen',
        platform: 'apk',
      );
      expect(result.hasUpdate, isFalse);
      expect(result.currentBuild, 12);
      expect(result.forceRequired, isFalse);
    });

    test('iOS：只提示 externalUrl，不下载不强更', () {
      final AppUpdateCheckResult result = AppUpdateCheckResult.fromJson(
        _payload(
          hasUpdate: true,
          forceUpdate: true,
          latest: _latest(9, externalUrl: 'https://apps.apple.com/app/id1'),
          platform: 'ios',
        ),
        appId: 'potatokid-home',
        platform: 'ios',
      );
      expect(result.hasUpdate, isTrue);
      expect(result.iosHintOnly, isTrue);
      expect(result.forceRequired, isFalse, reason: 'iOS 恒不强更');
      expect(result.canSilentlyDownload, isFalse, reason: 'iOS 不下载');
    });

    test('iOS 且服务端误报 forceUpdate=true → 客户端兜底不算强更', () {
      final result = AppUpdateCheckResult.fromJson(
        <String, dynamic>{
          'code': 0,
          'data': <String, dynamic>{
            'hasUpdate': true,
            'forceUpdate': true,
            'platform': 'ios',
            'current': <String, dynamic>{'version': '1.0.3', 'build': 8},
            'latest': _latest(9, externalUrl: 'https://example.com'),
          },
        },
        appId: 'potatokid-home',
        platform: 'ios',
      );
      expect(result.forceUpdate, isFalse);
      expect(result.forceRequired, isFalse);
    });

    test('无安装包且无外链 → 不能静默下载', () {
      final result = AppUpdateCheckResult.fromJson(
        _payload(hasUpdate: true, forceUpdate: false, latest: _latest(9)),
        appId: 'potatokid-screen',
        platform: 'apk',
      );
      expect(result.hasUpdate, isTrue);
      expect(result.canSilentlyDownload, isFalse);
    });
  });

  group('下载元数据', () {
    test('签名过期判定（提前 30s 视为过期）', () {
      final AppUpdateDownload expired = AppUpdateDownload.fromJson(<String, dynamic>{
        'url': 'http://x',
        'size': 1,
        'sha256': 'a',
        'filename': 'a.apk',
        'expiresAt': DateTime.now().subtract(const Duration(minutes: 1)).toIso8601String(),
      });
      expect(expired.isExpired, isTrue);
      final AppUpdateDownload fresh = AppUpdateDownload.fromJson(<String, dynamic>{
        'url': 'http://x',
        'size': 1,
        'sha256': 'a',
        'filename': 'a.apk',
        'expiresAt': DateTime.now().add(const Duration(minutes: 5)).toIso8601String(),
      });
      expect(fresh.isExpired, isFalse);
    });

    test('sha256 归一化为小写；缺字段时不可用', () {
      final AppUpdateDownload d = AppUpdateDownload.fromJson(<String, dynamic>{
        'url': 'http://x',
        'size': 100,
        'sha256': 'ABCDEF',
        'filename': 'a.apk',
      });
      expect(d.sha256, 'abcdef');
      expect(d.isUsable, isTrue);
      expect(AppUpdateDownload.fromJson(<String, dynamic>{}).isUsable, isFalse);
    });
  });
}

extension on AppUpdateCheckResult {
  /// 等价于 UI 侧 `showPill` 的前置条件（无更新时一律不展示）。
  bool showPillLike() => hasUpdate;
}
