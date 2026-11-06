import 'dart:async';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pscreen_screen/app/config/app_config.dart';
import 'package:pscreen_screen/app/config/app_constants.dart';
import 'package:pscreen_screen/app/config/screen_assets.dart';
import 'package:pscreen_screen/core/di/screen_injection.dart';
import 'package:pscreen_screen/core/logging/log_service.dart';
import 'package:pscreen_screen/core/utils/ptools_util.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 一个「可热更新」的数据文件：包内 `assets/datas` 提供默认值，GitHub 提供最新值。
class DataFile {
  const DataFile({required this.id, required this.fileName, required this.assetPath});

  /// 标识，用于日志与缓存键。
  final String id;

  /// 文件名（git 侧与包内同名）。
  final String fileName;

  /// 包内资源路径。
  final String assetPath;

  /// 本地持久化缓存键。存的是**原始文本**，所以解析规则改了也不用清缓存。
  String get prefsKey => 'data_file_v1_$id';

  /// GitHub 上的 raw 直链；请求前再经 [RawContentUrlResolver] 兜底还原
  /// （本身就是 raw 直链时原样返回）。
  String get gitUrl => '${AppConstants.githubDataBaseUrl}$fileName';
}

/// 数据文件同步层（全局单例）：让 `assets/datas` 下的这些文件
/// 既不依赖发新版就能改，又能在离线时正常工作。
///
/// 频道列表已改由服务端合并后直接下发（`final_channels.json`），这里只保留
/// 与频道无关的配置（天气城市）。
///
/// 取值优先级（高 → 低）：
/// 1. git 同步成功的内容（同时写入本地持久化缓存）；
/// 2. 本地持久化缓存（上次同步成功的结果，离线可用）；
/// 3. 包内 `assets/datas` 默认值；
/// 4. `.env` 里的同名配置（仅 [AppConfig] 那三项有，作兼容兜底）。
class DataFiles {
  DataFiles._();

  /// 全局单例。
  static final DataFiles instance = DataFiles._();

  // ===== 文件标识（供消费方引用，避免拼错字符串）=====
  static const String idWeatherCities = 'weather_cities';

  /// 纳入同步的文件清单。
  ///
  /// **新增文件**：这里加一条；若它需要自动写进某个全局配置，再到 [_consumers]
  /// 里接上消费方。
  static const List<DataFile> _files = <DataFile>[
    DataFile(id: idWeatherCities, fileName: 'weather_cities.txt', assetPath: 'assets/datas/weather_cities.txt'),
  ];

  /// 文件 id → 把「逗号分隔」的解析结果写进全局配置。
  static final Map<String, void Function(List<String> values)> _consumers =
      <String, void Function(List<String> values)>{
        idWeatherCities: (List<String> v) => AppConfig.weatherCities = v,
      };

  /// 单个文件的请求超时（都是小文本文件，不需要默认的 15/20 秒）。
  static const Duration _requestTimeout = Duration(seconds: 8);

  /// 整轮同步的总超时上限：超过就放弃 git，直接用本地值。
  ///
  /// 所有文件是**并发**请求的，所以这里的上限只需覆盖「最慢的一个文件」，
  /// 而不是全部之和。实测直连 GitHub 时单个请求 0.2s ~ 6s 都可能，
  /// 留 12s 既能容忍抖动，又不会在断网时把启动卡太久。
  static const Duration _syncTimeout = Duration(seconds: 60);

  /// 各文件当前生效的**原始文本**。
  final Map<String, String> _texts = <String, String>{};

  Future<void>? _localLoading;
  Future<void>? _syncing;
  int _revision = 0;

  /// 内容版本号：本地加载 / git 同步只要改动了内容就 +1。
  int get revision => _revision;

  /// 某个文件当前生效的原始文本；未加载/无内容时返回空串。
  String text(String id) => _texts[id] ?? '';

  /// 读本地值：持久化缓存优先，其次包内 assets 默认值。
  ///
  /// 只做本地 IO，很快，可在 `runApp` 前直接 await；幂等，重复调用共享同一次。
  Future<void> loadLocal() => _localLoading ??= _loadLocal();

  /// 启动时同步 git 最新值；幂等，并发调用共享同一次。
  Future<void> ensureSynced() => _syncing ??= _sync();

  /// 强制重新同步（「刷新频道」时用），不共享上一次的结果。
  Future<void> refresh() => _syncing = _sync();

  Future<void> _loadLocal() async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {
      // 取不到 SharedPreferences 就只用包内默认值。
    }
    for (final DataFile file in _files) {
      final String cached = prefs?.getString(file.prefsKey) ?? '';
      final String text = cached.trim().isNotEmpty ? cached : await _readAsset(file);
      if (text.trim().isEmpty) continue;
      _texts[file.id] = text;
      _apply(file.id, parseList(text));
      _revision++;
    }
  }

  Future<void> _sync() async {
    try {
      await _syncAll().timeout(_syncTimeout);
    } on TimeoutException {
      ScreenInjection.get<LogService>().warn('[DataFiles] git 同步超过 ${_syncTimeout.inSeconds}s，沿用本地值');
    } catch (e) {
      ScreenInjection.get<LogService>().warn('[DataFiles] git 同步失败，沿用本地值: $e');
    }
  }

  /// 并发同步全部文件：单文件失败只影响它自己，整体由 [_sync] 统一兜超时。
  Future<void> _syncAll() async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {
      // 缓存不可用时仍照常同步，只是不落盘。
    }
    await Future.wait(_files.map((DataFile f) => _syncOne(f, prefs)));
  }

  /// 同步单个文件：拉到有效内容就更新文本 + 落盘缓存，否则保留旧值。
  Future<void> _syncOne(DataFile file, SharedPreferences? prefs) async {
    try {
      // 文件在 /api/screen/ 下、需登录后访问：经 PtoolsUtil 拉取，遇到未登录会
      // 自动用保存的 Tools 账号/密码重登一次再取。
      final String text = await PtoolsUtil.fetchUrl(
        file.gitUrl,
        maxRetry: 0,
        connectTimeout: _requestTimeout,
        receiveTimeout: _requestTimeout,
      );
      // 空内容视为无效（可能是错误页/半截响应），保留旧值。
      if (text.trim().isEmpty) {
        ScreenInjection.get<LogService>().warn('[DataFiles] ${file.fileName} 内容为空，忽略');
        return;
      }
      _texts[file.id] = text;
      _apply(file.id, parseList(text));
      _revision++;
      await prefs?.setString(file.prefsKey, text);
      ScreenInjection.get<LogService>().info('[DataFiles] ${file.fileName} 已同步(${text.length} 字符)');
    } catch (e) {
      ScreenInjection.get<LogService>().warn('[DataFiles] ${file.fileName} 同步失败: $e');
    }
  }

  /// 把「逗号分隔」的解析结果写进登记过的消费方；空列表表示没读到有效内容。
  static void _apply(String id, List<String> values) {
    if (values.isEmpty) return;
    _consumers[id]?.call(values);
  }

  static Future<String> _readAsset(DataFile file) async {
    try {
      return await rootBundle.loadString(ScreenAssets.path(file.assetPath));
    } catch (_) {
      return '';
    }
  }

  /// 解析「逗号分隔」的清单文件（tv_name_order / tv_name_hide / weather_cities）。
  ///
  /// - `#` 起始的行为注释，整行忽略；
  /// - 换行与逗号等价，所以文件可以折成多行书写，整份当作一个列表；
  /// - 空白与空项丢弃。
  static List<String> parseList(String text) {
    final StringBuffer joined = StringBuffer();
    for (final String line in text.split('\n')) {
      final String trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      if (joined.isNotEmpty) joined.write(',');
      joined.write(trimmed);
    }
    return joined
        .toString()
        .split(',')
        .map((String s) => s.trim())
        .where((String s) => s.isNotEmpty)
        .toList(growable: false);
  }
}
