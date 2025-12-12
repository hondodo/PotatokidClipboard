import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:intl/intl.dart';
import 'package:potatokid_clipboard/framework/base/base_get_vm.dart';
import 'package:potatokid_clipboard/framework/utils/app_log.dart';
import 'package:potatokid_clipboard/pages/tools/search_web/widget/vm/search_bar_controller.dart';

const String singleKeywordTailKey = 'singleKeywordTailKey';
const String multipleKeywordsTailKey = 'multipleKeywordsTailKey';
const String singleKeywordSearchBarTag = 'singleKeywordSearchBar';
const String multipleKeywordsSearchBarTag = 'multipleKeywordsSearchBar';

class SearchWebController extends BaseGetVM {
  final TextEditingController searchNowController = TextEditingController();
  final TextEditingController multipleKeywordsController =
      TextEditingController();

  final SearchBarController singleKeywordSearchBarController = Get.put(
      SearchBarController(storageTailKey: singleKeywordTailKey),
      tag: singleKeywordSearchBarTag);
  final SearchBarController multipleKeywordsSearchBarController = Get.put(
      SearchBarController(storageTailKey: multipleKeywordsTailKey),
      tag: multipleKeywordsSearchBarTag);

  final RxList<String> multipleKeywords = <String>[].obs;

  final TextEditingController searchIntervalTimeController =
      TextEditingController();
  final TextEditingController searchIntervalErrorTimeController =
      TextEditingController();
  final TextEditingController searchIntervalCountFromController =
      TextEditingController();
  final TextEditingController searchIntervalCountToController =
      TextEditingController();
  final TextEditingController searchIntervalPauseTimeFromController =
      TextEditingController();
  final TextEditingController searchIntervalPauseTimeToController =
      TextEditingController();

  final isSearchingMultipleKeywords = false.obs;
  final multipleSearchStatusTips = ''.obs;

  Timer? multipleSearchTimer;

  @override
  void onInit() {
    super.onInit();
    multipleKeywordsController.addListener(onMultipleKeywordsChanged);
    try {
      searchIntervalTimeController.text =
          GetStorage().read<String>('searchIntervalTime') ?? '20';
      searchIntervalErrorTimeController.text =
          GetStorage().read<String>('searchIntervalErrorTime') ?? '60';
      searchIntervalCountFromController.text =
          GetStorage().read<String>('searchIntervalCountFrom') ?? '5';
      searchIntervalCountToController.text =
          GetStorage().read<String>('searchIntervalCountTo') ?? '10';
      searchIntervalPauseTimeFromController.text =
          GetStorage().read<String>('searchIntervalPauseTimeFrom') ?? '600';
      searchIntervalPauseTimeToController.text =
          GetStorage().read<String>('searchIntervalPauseTimeTo') ?? '600';
      multipleSearchStatusTips.value = '就绪'.tr;
    } catch (e) {
      Log.e('SearchWebController] 初始化搜索间隔设置失败: $e');
    }
  }

  @override
  void onClose() {
    multipleKeywordsController.removeListener(onMultipleKeywordsChanged);
    multipleKeywords.clear();
    super.onClose();
    Get.delete<SearchBarController>(tag: singleKeywordSearchBarTag);
    Get.delete<SearchBarController>(tag: multipleKeywordsSearchBarTag);
  }

  void onSingleKeywordSearch() {
    singleKeywordSearchBarController.onSearchNowPressed(
        keyword: searchNowController.text);
  }

  void onMultipleKeywordsChanged() {
    var keywords = multipleKeywordsController.text.split('\n');
    keywords = keywords.where((element) => element.trim().isNotEmpty).toList();
    keywords = keywords.toSet().toList();
    multipleKeywords.value = keywords;
  }

  void stopMultipleKeywordsSearch() {
    multipleSearchTimer?.cancel();
    multipleSearchTimer = null;
  }

  Future<void> waitMultipleSearchTimerTimeout() async {
    while (multipleSearchTimer?.isActive == true) {
      await Future.delayed(Duration(milliseconds: 500));
    }
  }

  Future<void> onMultipleKeywordsSearch() async {
    if (isSearchingMultipleKeywords.value) {
      stopMultipleKeywordsSearch();
      isSearchingMultipleKeywords.value = false;
      multipleSearchStatusTips.value = '就绪'.tr;
    } else {
      GetStorage()
          .write('searchIntervalTime', searchIntervalTimeController.text);
      GetStorage().write(
          'searchIntervalErrorTime', searchIntervalErrorTimeController.text);
      GetStorage().write(
          'searchIntervalCountFrom', searchIntervalCountFromController.text);
      GetStorage()
          .write('searchIntervalCountTo', searchIntervalCountToController.text);
      GetStorage().write('searchIntervalPauseTimeFrom',
          searchIntervalPauseTimeFromController.text);
      GetStorage().write('searchIntervalPauseTimeTo',
          searchIntervalPauseTimeToController.text);

      isSearchingMultipleKeywords.value = true;
      List<String> keywords = multipleKeywords;
      int totalCount = keywords.length;
      int totalIndex = 0;
      int searchIndex = 0;
      int searchCount =
          Random().nextInt(int.parse(searchIntervalCountToController.text)) +
              int.parse(searchIntervalCountFromController.text);
      int pauseTime = Random()
              .nextInt(int.parse(searchIntervalPauseTimeToController.text)) +
          int.parse(searchIntervalPauseTimeFromController.text);
      int delay =
          Random().nextInt(int.parse(searchIntervalErrorTimeController.text)) +
              int.parse(searchIntervalTimeController.text);
      bool isPauseTurn = false;
      for (var keyword in keywords) {
        if (searchIndex >= searchCount) {
          isPauseTurn = true;

          multipleSearchTimer = Timer(Duration(seconds: pauseTime), () {});
          pauseTime = Random().nextInt(
                  int.parse(searchIntervalPauseTimeToController.text)) +
              int.parse(searchIntervalPauseTimeFromController.text);
          searchCount = Random()
                  .nextInt(int.parse(searchIntervalCountToController.text)) +
              int.parse(searchIntervalCountFromController.text);
        } else {
          isPauseTurn = false;
          multipleSearchTimer = Timer(Duration(seconds: delay), () {});
          delay = Random()
                  .nextInt(int.parse(searchIntervalErrorTimeController.text)) +
              int.parse(searchIntervalTimeController.text);
        }
        String searchTimeText =
            '搜索时间：${DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now())}';
        String pauseTimeText =
            isPauseTurn ? '已达到本轮搜索次数，下次将在$pauseTime秒后继续搜索' : '下次搜索在$delay秒后';
        String infoText =
            '搜索中${totalIndex + 1}/$totalCount；本轮搜索${searchIndex + 1}/$searchCount，本轮搜索暂停$pauseTime秒；本次搜索间隔$delay秒';
        String tips =
            '当前关键词：$keyword\n$searchTimeText\n$pauseTimeText\n$infoText';
        multipleSearchStatusTips.value = tips;
        multipleKeywordsSearchBarController.onSearchNowPressed(
            keyword: keyword);
        searchIndex++;
        totalIndex++;
        if (totalIndex >= totalCount) {
          break;
        }
        await waitMultipleSearchTimerTimeout();
        if (!isSearchingMultipleKeywords.value) {
          return;
        }
      }
      stopMultipleKeywordsSearch();
      isSearchingMultipleKeywords.value = false;
      multipleSearchStatusTips.value = '就绪'.tr;
    }
  }
}
