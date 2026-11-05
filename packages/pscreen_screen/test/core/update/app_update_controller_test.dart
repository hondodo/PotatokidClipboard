import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_screen/core/update/app_update_api.dart';
import 'package:pscreen_screen/core/update/app_update_cache.dart';
import 'package:pscreen_screen/core/update/app_update_controller.dart';
import 'package:pscreen_screen/core/update/app_update_downloader.dart';
import 'package:pscreen_screen/core/update/app_update_models.dart';

class _FakeApi extends AppUpdateApi {
  _FakeApi(this.onCheck) : super(baseUrl: 'http://127.0.0.1:9');

  final Future<AppUpdateCheckResult> Function() onCheck;

  @override
  Future<AppUpdateCheckResult> check({
    required String appId,
    required String platform,
    required String version,
    required int build,
    String deviceId = '',
  }) =>
      onCheck();
}

class _FailingDownloader extends AppUpdateDownloader {
  @override
  Future<File> download({
    required String appId,
    required AppUpdateCheckResult result,
    required AppUpdateCache cache,
    required void Function(int received, int total) onProgress,
    Future<AppUpdateDownload?> Function()? renewDownload,
  }) async =>
      throw const AppUpdateDownloadException('安装包已被服务端清理（300008）', retryable: false);
}

AppUpdateCheckResult _apkResult({
  bool force = false,
  String sha = 'cafe',
  int size = 10,
}) =>
    AppUpdateCheckResult.fromJson(
      <String, dynamic>{
        'code': 0,
        'data': <String, dynamic>{
          'app': 'potatokid-home',
          'platform': 'apk',
          'hasUpdate': true,
          'forceUpdate': force,
          'current': <String, dynamic>{'version': '1.0.3', 'build': 8},
          'latest': <String, dynamic>{
            'releaseId': 'rel_9',
            'version': '1.0.4',
            'build': 9,
            'distribution': 'file',
            'fileAvailable': true,
          },
          'download': <String, dynamic>{
            'url': 'http://127.0.0.1:9/app.apk',
            'size': size,
            'sha256': sha,
            'filename': 'app.apk',
          },
        },
      },
      appId: 'potatokid-home',
      platform: 'apk',
    );

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('pk_update_ctrl_test_'));
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('查询失败 fail-open：只进入 failed，不产生强更拦截', () async {
    final controller = AppUpdateController(
      api: _FakeApi(() async => throw const AppUpdateException(100101, '应用服务器暂时不可用')),
      cache: AppUpdateCache(tmp),
      downloader: AppUpdateDownloader(),
    );
    controller.configure(const AppUpdateRuntime(
      appId: 'potatokid-home',
      platform: 'apk',
      baseUrl: 'http://127.0.0.1:9',
      version: '1.0.3',
      build: 8,
    ));
    await controller.check();
    expect(controller.state.phase, AppUpdatePhase.failed);
    expect(controller.state.forceBlocked, isFalse);
    expect(controller.state.showPill, isFalse, reason: '查询失败不应出现更新入口');
    controller.dispose();
  });

  test('iOS 仅提示：不进入下载，也不强更', () async {
    final result = AppUpdateCheckResult.fromJson(
      <String, dynamic>{
        'code': 0,
        'data': <String, dynamic>{
          'app': 'potatokid-home',
          'platform': 'ios',
          'hasUpdate': true,
          'forceUpdate': false,
          'current': <String, dynamic>{'version': '1.0.3', 'build': 8},
          'latest': <String, dynamic>{
            'releaseId': 'rel_ios',
            'version': '1.0.4',
            'build': 9,
            'distribution': 'external',
            'fileAvailable': false,
            'externalUrl': 'https://apps.apple.com/app/id1',
          },
          'download': null,
        },
      },
      appId: 'potatokid-home',
      platform: 'ios',
    );
    final controller = AppUpdateController(api: _FakeApi(() async => result), cache: AppUpdateCache(tmp));
    controller.configure(const AppUpdateRuntime(
      appId: 'potatokid-home',
      platform: 'ios',
      baseUrl: 'http://127.0.0.1:9',
      version: '1.0.3',
      build: 8,
    ));
    await controller.check();
    expect(controller.state.phase, AppUpdatePhase.idle);
    expect(controller.state.result!.iosHintOnly, isTrue);
    expect(controller.state.forceBlocked, isFalse);
    controller.dispose();
  });

  test('缓存命中 + 强更 → ready 且 forceBlocked=true（不发起下载）', () async {
    final List<int> bytes = List<int>.generate(10, (int i) => i);
    final AppUpdateCache cache = AppUpdateCache(tmp);
    final File probe = File('${tmp.path}/probe.bin')..writeAsBytesSync(bytes);
    final String realSha = await AppUpdateCache.sha256OfFile(probe);
    probe.deleteSync();
    final File file = cache.finalFile(appId: 'potatokid-home', releaseId: 'rel_9', sha256: realSha);
    file.writeAsBytesSync(bytes);
    final AppUpdateCheckResult forced = _apkResult(force: true, sha: realSha, size: bytes.length);

    final controller = AppUpdateController(
      api: _FakeApi(() async => forced),
      cache: cache,
      downloader: AppUpdateDownloader(),
    );
    controller.configure(const AppUpdateRuntime(
      appId: 'potatokid-home',
      platform: 'apk',
      baseUrl: 'http://127.0.0.1:9',
      version: '1.0.3',
      build: 8,
    ));
    await controller.check();
    // 下载是后台异步任务；等它完成缓存复用。
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(controller.state.phase, AppUpdatePhase.ready);
    expect(controller.state.forceBlocked, isTrue);
    expect(controller.state.cachedPath, isNotNull);
    controller.dispose();
  });

  test('下载失败（300008）→ failed 而非 ready：不阻断使用', () async {
    final controller = AppUpdateController(
      api: _FakeApi(() async => _apkResult()),
      cache: AppUpdateCache(tmp),
      downloader: _FailingDownloader(),
    );
    controller.configure(const AppUpdateRuntime(
      appId: 'potatokid-home',
      platform: 'apk',
      baseUrl: 'http://127.0.0.1:9',
      version: '1.0.3',
      build: 8,
    ));
    await controller.check();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(controller.state.phase, AppUpdatePhase.failed);
    expect(controller.state.forceBlocked, isFalse);
    controller.dispose();
  });
}
