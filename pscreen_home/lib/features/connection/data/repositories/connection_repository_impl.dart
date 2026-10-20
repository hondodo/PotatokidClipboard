import 'package:pscreen_home/app/config/app_config.dart';
import 'package:pscreen_home/core/network/ha_ws_client.dart';
import 'package:pscreen_home/features/connection/domain/repositories/connection_repository.dart';

/// 连接数据仓库实现：从 [AppConfig] 取连接信息，委托给 WebSocket 客户端。
class ConnectionRepositoryImpl implements ConnectionRepository {
  ConnectionRepositoryImpl({required this.client});

  final HaWsClient client;

  @override
  Stream<HaConnectionInfo> watchConnection() => client.watchConnection();

  @override
  HaConnectionInfo get current => client.connection;

  @override
  Future<void> connect() => client.connect(wsUrl: AppConfig.haWsUrl, token: AppConfig.haToken);

  @override
  Future<void> disconnect() => client.disconnect();
}
