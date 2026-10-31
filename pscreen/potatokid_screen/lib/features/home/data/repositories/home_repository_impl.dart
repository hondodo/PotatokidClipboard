import 'package:potatokid_screen/features/home/data/datasources/remote/home_api_service.dart';
import 'package:potatokid_screen/features/home/data/models/home_model.dart';
import 'package:potatokid_screen/features/home/domain/repositories/home_repository.dart';

/// 首页仓库实现：调用接口定义层，把原始 JSON 转换为领域模型。
/// 网络异常在此处自然向上冒泡，由 BLoC 统一捕获并转为 State。
class HomeRepositoryImpl implements HomeRepository {
  HomeRepositoryImpl({HomeApiService? api}) : _api = api ?? HomeApiService();

  final HomeApiService _api;

  @override
  Future<List<HomeModel>> fetchHomeList() async {
    final List<dynamic> raw = await _api.fetchHomeList();
    return raw
        .whereType<Map<String, dynamic>>()
        .map(HomeModel.fromJson)
        .toList(growable: false);
  }
}
