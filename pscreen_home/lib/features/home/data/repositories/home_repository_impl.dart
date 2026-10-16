import 'package:pscreen_home/core/logging/log_service.dart';
import 'package:pscreen_home/core/network/ha_ws_client.dart';
import 'package:pscreen_home/core/network/net_exceptions.dart';
import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';
import 'package:pscreen_home/features/home/domain/repositories/home_repository.dart';

/// 主页数据仓库实现：通过 WebSocket 客户端访问 Home Assistant。
class HomeRepositoryImpl implements HomeRepository {
  HomeRepositoryImpl({
    required this._client,
    required this._log,
  });

  final HaWsClient _client;
  final LogService _log;

  @override
  Future<List<HaEntityStateModel>> fetchStates() async {
    final Map<String, dynamic> msg = await _client.request('get_states');
    final Object? result = msg['result'];
    if (result is! List) throw const HaDataException('get_states 返回结构异常');
    return result
        .whereType<Map>()
        .map((e) => HaEntityStateModel.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  @override
  Stream<HaEntityStateModel> watchStateChanges() async* {
    await for (final Map<String, dynamic> raw in _client.stateChanged) {
      try {
        yield HaEntityStateModel.fromJson(raw);
      } catch (e) {
        _log.warn('state_changed 解析失败：$e');
      }
    }
  }

  @override
  Future<void> setEntityPower({
    required String entityId,
    required bool turnOn,
  }) {
    final String domain = entityId.split('.').first;
    return _client.callService(
      domain: domain,
      service: turnOn ? 'turn_on' : 'turn_off',
      entityId: entityId,
    );
  }
}
