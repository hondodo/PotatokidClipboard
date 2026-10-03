import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:potatokid_screen/app/config/app_config.dart';
import 'package:potatokid_screen/app/config/app_constants.dart';
import 'package:potatokid_screen/core/di/injection.dart';
import 'package:potatokid_screen/core/logging/log_service.dart';
import 'package:potatokid_screen/core/network/dio_manager.dart';
import 'package:potatokid_screen/core/network/raw_content_url_resolver.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 一个「可热更新」的数据文件：包内 `assets/datas` 提供默认值，GitHub 提供最新值。
class DataFile {
  const DataFile({
    required this.id,
    required this.fileName,
    required this.assetPath,
  });

  /// 标识，用于日志与缓存键。
  final String id;

  /// 文件名（git 侧与包内同名）。
  final String fileName;

  /// 包内资源路径。
  final String assetPath;

  /// 本地持久化缓存键。存的是**原始文本**，所以解析规则改了也不用清缓存。
  String get prefsKey => 'data_file_v1_$id';

  /// GitHub 上的「文件页」地址；请求前由 [RawContentUrlResolver] 还原成 raw 直链。
  String get gitUrl => '${AppConstants.githubDataBaseUrl}$fileName';
}

/// 数据文件同步层（全局单例）：让「频道顺序/隐藏频道/天气城市」这类配置
/// 既不依赖发新版就能改，又能在离线时正常工作。
///
/// 取值优先级（高 → 低）：
/// 1. git 同步成功的内容（同时写入本地持久化缓存）；
/// 2. 本地持久化缓存（上次同步成功的结果，离线可用）；
/// 3. 包内 `assets/datas` 默认值；
/// 4. `.env` 里的同名配置（仅作兼容兜底，见 [AppConfig.initialize]）。
///
/// 启动流程：`main()` 先 [loadLocal] 拿到可用值（缓存 → 包内），
/// 再 [ensureSynced] 拉取 git 最新值覆盖；「刷新频道」走 [refresh] 强制重拉。
/// 任何一步失败/超时都保留已有值，绝不阻断启动与播放。
class DataFiles {
  DataFiles._();

  /// 全局单例。
  static final DataFiles instance = DataFiles._();

  /// 纳入同步的文件清单。
  ///
  /// **新增文件**：这里加一条，并在 [_consumers] 里接上它的消费方即可。
  static const List<DataFile> _files = <DataFile>[
    DataFile(
      id: 'tv_name_order',
      fileName: 'tv_name_order.txt',
      assetPath: 'assets/datas/tv_name_order.txt',
    ),
    DataFile(
      id: 'tv_name_hide',
      fileName: 'tv_name_hide.txt',
      assetPath: 'assets/datas/tv_name_hide.txt',
    ),
    DataFile(
      id: 'weather_cities',
      fileName: 'weather_cities.txt',
      assetPath: 'assets/datas/weather_cities.txt',
    ),
  ];

  /// 文件 id → 把解析结果写进消费方。
  static final Map<String, void Function(List<String> values)> _consumers =
      <String, void Function(List<String> values)>{
    'tv_name_order': (List<String> v) => AppConfig.tvNameOrder = v,
    'tv_name_hide': (List<String> v) => AppConfig.tvNameHide = v,
    'weather_cities': (List<String> v) => AppConfig.weatherCities = v,
  };

  /// 单个文件的请求超时（3 个小文本文件，不需要默认的 15/20 秒）。
  static const Duration _requestTimeout = Duration(seconds: 8);

  /// 整轮同步的总超时上限：超过就放弃 git，直接用本地值。
  ///
  /// 三个文件是**并发**请求的，所以这里的上限只需覆盖「最慢的一个文件」，
  /// 而不是三者之和。实测镜像中转抖动较大（单个请求 0.2s ~ 6s 都可能），
  /// 留 10s 既能容忍抖动，又不会在断网时把启动卡太久。
  static const Duration _syncTimeout = Duration(seconds: 10);

  Future<void>? _syncing;

  /// 读本地值：持久化缓存优先，其次包内 assets 默认值。
  ///
  /// 只做本地 IO，很快，可在 `runApp` 前直接 await。
  Future<void> loadLocal() async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {
      // 取不到 SharedPreferences 就只用包内默认值。
    }
    for (final DataFile file in _files) {
      final String cached = prefs?.getString(file.prefsKey) ?? '';
      final bool cacheUsable = parseList(cached).isNotEmpty;
      _apply(file.id, parseList(cacheUsable ? cached : await _readAsset(file)));
    }
  }

  /// 启动时同步 git 最新值；幂等，并发调用共享同一次。
  Future<void> ensureSynced() => _syncing ??= _sync();

  /// 强制重新同步（「刷新频道」时用），不共享上一次的结果。
  Future<void> refresh() => _syncing = _sync();

  Future<void> _sync() async {
    try {
      await _syncAll().timeout(_syncTimeout);
    } on TimeoutException {
      Injection.get<LogService>().warn(
        '[DataFiles] git 同步超过 ${_syncTimeout.inSeconds}s，沿用本地值',
      );
    } catch (e) {
      Injection.get<LogService>().warn('[DataFiles] git 同步失败，沿用本地值: $e');
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

  /// 同步单个文件：拉到有效内容就写回消费方并落盘缓存，否则保留旧值。
  Future<void> _syncOne(DataFile file, SharedPreferences? prefs) async {
    try {
      final dynamic data = await DioManager().send(
        // 配置里是 GitHub 文件页地址，这里还原成 raw 直链并套加速前缀。
        url: RawContentUrlResolver.toFetchable(file.gitUrl),
        responseType: ResponseType.plain,
        notTipNetError: true,
        maxRetry: 0,
        connectTimeout: _requestTimeout,
        receiveTimeout: _requestTimeout,
      );
      final String text = data is String ? data : '';
      final List<String> values = parseList(text);
      // 空内容视为无效（可能是错误页/半截响应），保留旧值。
      if (values.isEmpty) {
        Injection.get<LogService>().warn('[DataFiles] ${file.fileName} 内容为空，忽略');
        return;
      }
      _apply(file.id, values);
      await prefs?.setString(file.prefsKey, text);
      Injection.get<LogService>().info(
        '[DataFiles] ${file.fileName} 已同步(${values.length} 项)',
      );
    } catch (e) {
      Injection.get<LogService>().warn('[DataFiles] ${file.fileName} 同步失败: $e');
    }
  }

  /// 把解析结果写进消费方；空列表表示「没读到有效内容」，保留原值。
  static void _apply(String id, List<String> values) {
    if (values.isEmpty) return;
    _consumers[id]?.call(values);
  }

  static Future<String> _readAsset(DataFile file) async {
    try {
      return await rootBundle.loadString(file.assetPath);
    } catch (_) {
      return '';
    }
  }

  /// 解析「逗号分隔」的清单文件（[DataFile] 指向的三个文件都是这个格式）。
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