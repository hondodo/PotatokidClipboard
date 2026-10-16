import 'package:pscreen_home/core/network/ha_ws_client.dart';

/// 连接数据仓库（抽象接口，只定义方法签名）
abstract class ConnectionRepository {
  /// 连接状态流
  Stream<HaConnectionInfo> watchConnection();

  /// 当前连接状态
  HaConnectionInfo get current;

  /// 发起连接（幂等）
  Future<void> connect();

  /// 主动断开（不再自动重连）
  Future<void> disconnect();
}
