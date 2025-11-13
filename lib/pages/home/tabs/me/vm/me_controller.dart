import 'package:get/get.dart';
import 'package:potatokid_clipboard/framework/base/base_get_vm.dart';
import 'package:potatokid_clipboard/pages/home/tabs/me/model/ip_model.dart';
import 'package:potatokid_clipboard/pages/home/tabs/me/repository/me_repository.dart';
import 'package:potatokid_clipboard/user/model/user_model.dart';
import 'package:potatokid_clipboard/user/user_service.dart';

class MeController extends BaseGetVM {
  Rx<UserModel> get user => Get.find<UserService>().user;
  final Rx<IpModel?> ipInfoModel = Rx<IpModel?>(null);

  @override
  void onInit() {
    super.onInit();
    loadIpInfo().responseWithStatus(this);
  }

  Future<void> loadIpInfo() async {
    ipInfoModel.value = await MeRepository().getIpInfo();
  }

  Future<void> onRefresh() async {
    loadIpInfo().responseWithStatus(this);
  }
}
