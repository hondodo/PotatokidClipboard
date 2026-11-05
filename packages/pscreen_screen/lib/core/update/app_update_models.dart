import 'package:flutter/foundation.dart';

/// 应用更新：一次查询结果（本地 pscreen_server `/api/app_update/check` 透传
/// yuntu app_server 的响应结构）。
///
/// 判定规则（与服务端一致，`version` 不参与比较）：
/// - `hasUpdate = latest.build > current.build`；
/// - 客户端领先（`current.build > latest.build`）或相等 → 无更新；
/// - `forceUpdate` 只对「当前平台 latest」生效，iOS 恒不强更。
@immutable
class AppUpdateCheckResult {
  const AppUpdateCheckResult({
    required this.appId,
    required this.platform,
    required this.currentVersion,
    required this.currentBuild,
    required this.hasUpdate,
    required this.forceUpdate,
    this.latest,
    this.download,
    this.notice,
  });

  final String appId;
  final String platform;
  final String currentVersion;
  final int currentBuild;
  final bool hasUpdate;
  final bool forceUpdate;
  final AppUpdateRelease? latest;
  final AppUpdateDownload? download;

  /// 服务端附带的提示文案（查询失败时的降级说明等）。
  final String? notice;

  /// 查询失败时的降级占位（`hasUpdate=false`，UI 不展示任何更新入口）。
  factory AppUpdateCheckResult.none({
    required String appId,
    required String platform,
    String currentVersion = '',
    int currentBuild = 0,
    String? notice,
  }) =>
      AppUpdateCheckResult(
        appId: appId,
        platform: platform,
        currentVersion: currentVersion,
        currentBuild: currentBuild,
        hasUpdate: false,
        forceUpdate: false,
        notice: notice,
      );

  bool get isIos => platform == 'ios';

  /// iOS 只能提示外部链接：不下载、不强更。
  bool get iosHintOnly => isIos && hasUpdate && latest?.externalUrl != null;

  /// 可以静默下载（Android/桌面自托管安装包）。
  bool get canSilentlyDownload => hasUpdate && !isIos && download != null;

  /// 下载并校验通过后必须进入不可关闭的更新页。
  bool get forceRequired => hasUpdate && forceUpdate && !isIos;

  /// 服务端返回了错误码（本地代理/上游都沿用 `{code,msg,data}`）。
  factory AppUpdateCheckResult.fromJson(
    Map<String, dynamic> json, {
    required String appId,
    required String platform,
  }) {
    final Map<String, dynamic> data =
        json['data'] is Map ? Map<String, dynamic>.from(json['data'] as Map) : json;
    final Map<String, dynamic> current =
        data['current'] is Map ? Map<String, dynamic>.from(data['current'] as Map) : <String, dynamic>{};
    final Map<String, dynamic>? latestRaw =
        data['latest'] is Map ? Map<String, dynamic>.from(data['latest'] as Map) : null;
    final Map<String, dynamic>? downloadRaw =
        data['download'] is Map ? Map<String, dynamic>.from(data['download'] as Map) : null;
    return AppUpdateCheckResult(
      appId: (data['app'] as String?)?.trim().isNotEmpty == true ? data['app'] as String : appId,
      platform: (data['platform'] as String?)?.trim().isNotEmpty == true
          ? data['platform'] as String
          : platform,
      currentVersion: current['version']?.toString() ?? '',
      currentBuild: _asInt(current['build']),
      hasUpdate: data['hasUpdate'] == true,
      // 服务端已把 iOS 归一化为 false，这里再兜一层，避免旧服务端漏配。
      forceUpdate: data['forceUpdate'] == true && platform != 'ios',
      latest: latestRaw == null ? null : AppUpdateRelease.fromJson(latestRaw),
      download: downloadRaw == null ? null : AppUpdateDownload.fromJson(downloadRaw),
      notice: data['msg'] is String ? data['msg'] as String : null,
    );
  }

  AppUpdateCheckResult copyWithDownload(AppUpdateDownload value) => AppUpdateCheckResult(
        appId: appId,
        platform: platform,
        currentVersion: currentVersion,
        currentBuild: currentBuild,
        hasUpdate: hasUpdate,
        forceUpdate: forceUpdate,
        latest: latest,
        download: value,
        notice: notice,
      );

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

/// 服务端维护的最新版本元数据（`latest` 字段）。
@immutable
class AppUpdateRelease {
  const AppUpdateRelease({
    required this.releaseId,
    required this.version,
    required this.build,
    required this.distribution,
    required this.fileAvailable,
    this.externalUrl,
    this.forceUpdate = false,
    this.notes = '',
    this.publishedAt,
  });

  final String releaseId;
  final String version;
  final int build;
  final String distribution;
  final bool fileAvailable;
  final String? externalUrl;
  final bool forceUpdate;
  final String notes;
  final DateTime? publishedAt;

  factory AppUpdateRelease.fromJson(Map<String, dynamic> json) => AppUpdateRelease(
        releaseId: json['releaseId']?.toString() ?? '',
        version: json['version']?.toString() ?? '',
        build: AppUpdateCheckResult._asInt(json['build']),
        distribution: json['distribution']?.toString() ?? 'file',
        fileAvailable: json['fileAvailable'] == true,
        externalUrl: (json['externalUrl'] as String?)?.trim().isEmpty == true
            ? null
            : json['externalUrl'] as String?,
        forceUpdate: json['forceUpdate'] == true,
        notes: json['notes']?.toString() ?? '',
        publishedAt: DateTime.tryParse(json['publishedAt']?.toString() ?? '')?.toLocal(),
      );
}

/// 签名下载地址（TTL 默认 600s，过期需重新查询）。
@immutable
class AppUpdateDownload {
  const AppUpdateDownload({
    required this.url,
    required this.size,
    required this.sha256,
    required this.filename,
    this.expiresAt,
  });

  final String url;
  final int size;
  final String sha256;
  final String filename;
  final DateTime? expiresAt;

  factory AppUpdateDownload.fromJson(Map<String, dynamic> json) => AppUpdateDownload(
        url: json['url']?.toString() ?? '',
        size: AppUpdateCheckResult._asInt(json['size']),
        sha256: json['sha256']?.toString().toLowerCase() ?? '',
        filename: json['filename']?.toString() ?? 'update.apk',
        expiresAt: DateTime.tryParse(json['expiresAt']?.toString() ?? '')?.toLocal(),
      );

  bool get isUsable => url.isNotEmpty && sha256.isNotEmpty && size > 0;

  /// 签名已过期或客户端时钟偏差较大时，提前 30s 视为过期。
  bool get isExpired {
    final DateTime? exp = expiresAt;
    if (exp == null) return false;
    return DateTime.now().add(const Duration(seconds: 30)).isAfter(exp);
  }
}

/// 平台值映射：yuntu 用 `apk` 而不是 `android`；web 不参与更新检查。
String? updatePlatformOf(TargetPlatform platform) {
  switch (platform) {
    case TargetPlatform.android:
      return 'apk';
    case TargetPlatform.iOS:
      return 'ios';
    case TargetPlatform.macOS:
      return 'macos';
    case TargetPlatform.windows:
      return 'windows';
    case TargetPlatform.linux:
      return 'linux';
    case TargetPlatform.fuchsia:
      return null;
  }
}
