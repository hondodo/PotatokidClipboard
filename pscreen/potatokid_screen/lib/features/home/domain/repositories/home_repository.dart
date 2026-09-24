import 'package:potatokid_screen/features/home/data/models/home_model.dart';

/// 首页领域仓库接口（纯抽象，只定义方法签名）
abstract class HomeRepository {
  Future<List<HomeModel>> fetchHomeList();
}
