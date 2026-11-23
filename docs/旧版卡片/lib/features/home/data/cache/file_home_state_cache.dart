import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:pscreen_home/app/config/ha_config.dart';
import 'package:pscreen_home/core/utils/ha_host_key.dart';
import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';
import 'package:pscreen_home/features/home/domain/repositories/home_state_cache.dart';
import 'package:pscreen_screen/core/logging/log_service.dart';

/// 基于文件 + gzip 的首页实体状态快照。
///
/// 全量实体（一千多个）序列化后约 700KB，压缩后约 100KB：
/// 放 SharedPreferences 会让每次设置写入都重写整份 XML，因此单独存文件。
/// 快照按 HA 地址隔离，切换服务器后不会误展示旧家庭的卡片。
class FileHomeStateCache implements HomeStateCache {
  FileHomeStateCache({
    required LogService log,
    String Function()? hostProvider,
    Future<Directory> Function()? directoryProvider,
  }) : _log = log,
       _hostProvider = hostProvider ?? (() => HaConfig.haHost),
       _directoryProvider = directoryProvider;

  static const int _version = 1;
  static const String _fileName = 'ha_home_states_v1.json.gz';

  final LogService _log;
  final String Function() _hostProvider;
  final Future<Directory> Function()? _directoryProvider;

  @override
  Future<List<HaEntityStateModel>?> read() async {
    try {
      final File file = await _file();
      if (!await file.exists()) return null;
      final String raw = utf8.decode(gzip.decode(await file.readAsBytes()));
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final Map<String, dynamic> payload = Map<String, dynamic>.from(decoded);
      if (payload['version'] != _version) return null;
      if (payload['host'] != normalizeHaHost(_hostProvider())) {
        _log.debug('实体快照与当前 HA 地址不匹配，忽略快照');
        return null;
      }
      final Object? rawStates = payload['states'];
      if (rawStates is! List) return null;
      final List<HaEntityStateModel> states = <HaEntityStateModel>[];
      for (final Object? raw in rawStates) {
        if (raw is! Map) continue;
        try {
          states.add(
            HaEntityStateModel.fromJson(Map<String, dynamic>.from(raw)),
          );
        } catch (_) {
          // 单条损坏不影响其余实体。
        }
      }
      return states.isEmpty ? null : states;
    } catch (e) {
      _log.warn('读取实体快照失败，忽略快照：$e');
      return null;
    }
  }

  @override
  Future<void> write(List<HaEntityStateModel> states) async {
    if (states.isEmpty) return;
    try {
      // 让当前帧先完成：序列化一千多个实体需要几十毫秒，
      // 不要在 LoadHome 刚 emit 完就卡住 UI。
      await Future<void>.delayed(Duration.zero);
      final File file = await _file();
      final Map<String, dynamic> payload = <String, dynamic>{
        'version': _version,
        'host': normalizeHaHost(_hostProvider()),
        'savedAt': DateTime.now().toUtc().toIso8601String(),
        'states': <Map<String, dynamic>>[
          for (final HaEntityStateModel state in states) state.toJson(),
        ],
      };
      final List<int> bytes = gzip.encode(utf8.encode(jsonEncode(payload)));
      final File temp = File('${file.path}.tmp');
      await temp.parent.create(recursive: true);
      await temp.writeAsBytes(bytes, flush: true);
      if (await file.exists()) {
        await file.delete();
      }
      await temp.rename(file.path);
      _log.debug('已写入 ${states.length} 个实体快照（${bytes.length} 字节）');
    } catch (e) {
      _log.warn('写入实体快照失败：$e');
    }
  }

  Future<File> _file() async {
    final Directory directory =
        await (_directoryProvider?.call() ?? getApplicationSupportDirectory());
    return File('${directory.path}${Platform.pathSeparator}$_fileName');
  }
}
