import 'package:potatokid_screen/features/iptv/data/datasources/remote/iptv_api_service.dart';
import 'package:potatokid_screen/features/iptv/domain/models/iptv_channel.dart';
import 'package:potatokid_screen/features/iptv/domain/repositories/iptv_repository.dart';

/// IPTV 仓库实现：调用数据源拉取原始文本，网络异常自然向上冒泡，
/// 由 BLoC 统一捕获并转为 State。
class IptvRepositoryImpl implements IptvRepository {
  IptvRepositoryImpl({IptvApiService? api}) : _api = api ?? IptvApiService();

  final IptvApiService _api;

  @override
  Future<List<IptvChannel>> fetchChannels() => _api.fetchChannels();
}