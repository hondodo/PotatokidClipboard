import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:potatokid_clipboard/framework/base/base_get_vm.dart';
import 'package:potatokid_clipboard/framework/utils/app_log.dart';
import 'package:potatokid_clipboard/pages/tools/search_web/model/search_provider_model.dart';
import 'package:potatokid_clipboard/utils/device_utils.dart';
import 'package:url_launcher/url_launcher.dart';

class SearchBarController extends BaseGetVM {
  final TextEditingController searchNowTailController = TextEditingController();
  final RxList<SearchProviderModel> searchProviders =
      <SearchProviderModel>[].obs;
  final Rx<SearchProviderModel> selectedSearchProvider =
      SearchProviderModel(id: '', name: '', url: '', icon: '').obs;

  SearchBarController({String? storageTailKey}) {
    if (storageTailKey != null) {
      _storageTailKey = storageTailKey;
    }
  }

  String _storageTailKey = 'searchBarKeywordTail';

  @override
  void onInit() {
    super.onInit();
    var args = Get.arguments;
    if (args is Map<String, dynamic> && args['_storageTailKey'] != null) {
      var storageTailKeyValue = args['_storageTailKey'];
      if (storageTailKeyValue is String) {
        _storageTailKey = storageTailKeyValue;
      }
    }
    var bing = SearchProviderModel(
        id: 'bing',
        name: '必应'.tr,
        url: DeviceUtils.instance.isDesktop()
            ? 'https://www.bing.com/search?q='
            : 'https://cn.bing.com/search?q=',
        icon: 'https://www.bing.com/favicon.ico',
        tail: DeviceUtils.instance.isDesktop()
            ? '&FORM=SSQNT1&adppc=EDGEESS&PC=NMTS'
            : '&setmkt=zh-CN&PC=EMMX01&form=LWS002&scope=web');
    searchProviders.add(SearchProviderModel(
      id: 'baidu',
      name: '百度'.tr,
      url: 'https://www.baidu.com/s?wd=',
      icon: 'https://www.baidu.com/favicon.ico',
    ));
    searchProviders.add(bing);
    selectedSearchProvider.value = bing;
    searchNowTailController.text =
        getSearchNowTail(selectedSearchProvider.value);
    searchNowTailController.addListener(onSearchNowTailChanged);
  }

  @override
  void onClose() {
    searchNowTailController.removeListener(onSearchNowTailChanged);
    searchNowTailController.dispose();
    super.onClose();
  }

  Future<void> search(SearchProviderModel model, String keyword) async {
    String tail = getSearchNowTail(model);
    var url = model.url + Uri.encodeComponent(keyword) + tail;
    await launchUrl(Uri.parse(url));
  }

  Future<void> onSearchNowPressed({required String keyword}) async {
    await search(selectedSearchProvider.value, keyword);
  }

  Future<void> onSearchProviderChanged(SearchProviderModel model) async {
    selectedSearchProvider.value = model;
    searchNowTailController.removeListener(onSearchNowTailChanged);
    searchNowTailController.text = getSearchNowTail(model);
    searchNowTailController.addListener(onSearchNowTailChanged);
  }

  String getSearchNowTailKey(SearchProviderModel model) {
    return '$_storageTailKey:${model.id}';
  }

  Future<void> onSearchNowTailChanged() async {
    String tail = searchNowTailController.text.trim();
    String key = getSearchNowTailKey(selectedSearchProvider.value);
    await GetStorage().write(key, tail);
  }

  String getSearchNowTail(SearchProviderModel model) {
    String key = getSearchNowTailKey(model);
    try {
      return GetStorage().read<String>(key) ?? model.tail;
    } catch (e) {
      Log.e('SearchBarController] 获取附加参数失败: $e');
      return model.tail;
    }
  }
}
