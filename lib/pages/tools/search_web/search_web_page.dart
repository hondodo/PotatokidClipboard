import 'package:flutter/material.dart';
import 'package:get/get_utils/src/extensions/internacionalization.dart';
import 'package:potatokid_clipboard/components/app_text_field.dart';
import 'package:potatokid_clipboard/framework/base/base_stateless_sub_widget.dart';
import 'package:potatokid_clipboard/framework/theme/app_text_theme.dart';
import 'package:potatokid_clipboard/pages/tools/search_web/vm/search_web_controller.dart';
import 'package:potatokid_clipboard/pages/tools/search_web/widget/search_bar_widget.dart';

class SearchWebPage extends BaseStatelessSubWidget<SearchWebController> {
  const SearchWebPage({super.key});

  @override
  Widget buildBody(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, top: 16),
            child: SearchBarWidget(controllerTag: singleKeywordSearchBarTag),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, top: 16),
            child: Row(
              children: [
                Expanded(
                  child: AppTextField(
                    controller: controller.searchNowController,
                    hintText: '请输入搜索内容'.tr,
                  ),
                ),
                SizedBox(width: 8),
                ElevatedButton(
                    onPressed: () => controller.onSingleKeywordSearch(),
                    child: Text('搜索'.tr, style: AppTextTheme.textStyle.body)),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, top: 16),
            child: Divider(
              color: AppTextTheme.hintColor,
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, top: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('搜索多个关键词'.tr, style: AppTextTheme.textStyle.body),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, top: 16),
            child: Text(controller.multipleSearchStatusTips.value,
                style: AppTextTheme.textStyle.body
                    .setColor(AppTextTheme.primaryColor)),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, top: 16),
            child: SearchBarWidget(controllerTag: multipleKeywordsSearchBarTag),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, top: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('关键词（每个一行）'.tr, style: AppTextTheme.textStyle.body),
                SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => controller.onMultipleKeywordsSearch(),
                  child: Text(
                      controller.isSearchingMultipleKeywords.value
                          ? '停止'.tr
                          : '搜索'.tr,
                      style: AppTextTheme.textStyle.body),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, top: 16),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: 120),
              child: TextField(
                controller: controller.multipleKeywordsController,
                maxLines: null,
                style: AppTextTheme.textStyle.body,
                decoration: InputDecoration(
                  hintText: '请输入多个关键词，每个一行'.tr,
                  hintStyle: AppTextTheme.textStyle.hint,
                  border: OutlineInputBorder(
                    borderSide: BorderSide(color: AppTextTheme.hintColor),
                  ),
                  contentPadding: EdgeInsets.all(8),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: AppTextTheme.primaryColor),
                  ),
                ),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, top: 16),
            child: Text(
                '去重和去掉空白后，一共@count个关键词'.trParams({
                  'count': controller.multipleKeywords.length.toString(),
                }),
                style: AppTextTheme.textStyle.body),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, top: 16),
            child: Wrap(
              spacing: 4,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('每次搜索间隔'.tr, style: AppTextTheme.textStyle.body),
                SizedBox(
                  width: 40,
                  child: AppTextField(
                    controller: controller.searchIntervalTimeController,
                    hintText: '间隔'.tr,
                    keyboardType: TextInputType.number,
                  ),
                ),
                Text('秒+0到'.tr, style: AppTextTheme.textStyle.body),
                SizedBox(
                  width: 40,
                  child: AppTextField(
                    controller: controller.searchIntervalErrorTimeController,
                    hintText: '随机'.tr,
                    keyboardType: TextInputType.number,
                  ),
                ),
                Text('秒。当搜索'.tr, style: AppTextTheme.textStyle.body),
                SizedBox(
                  width: 40,
                  child: AppTextField(
                    controller: controller.searchIntervalCountFromController,
                    hintText: '次数'.tr,
                    keyboardType: TextInputType.number,
                  ),
                ),
                Text('次+0到'.tr, style: AppTextTheme.textStyle.body),
                SizedBox(
                  width: 40,
                  child: AppTextField(
                    controller: controller.searchIntervalCountToController,
                    hintText: '次数'.tr,
                    keyboardType: TextInputType.number,
                  ),
                ),
                Text('次时，暂停'.tr, style: AppTextTheme.textStyle.body),
                SizedBox(
                  width: 60,
                  child: AppTextField(
                    controller:
                        controller.searchIntervalPauseTimeFromController,
                    hintText: '暂停'.tr,
                    keyboardType: TextInputType.number,
                  ),
                ),
                Text('秒+0到'.tr, style: AppTextTheme.textStyle.body),
                SizedBox(
                  width: 60,
                  child: AppTextField(
                    controller: controller.searchIntervalPauseTimeToController,
                    hintText: '暂停'.tr,
                    keyboardType: TextInputType.number,
                  ),
                ),
                Text('秒时，继续搜索。'.tr, style: AppTextTheme.textStyle.body),
              ],
            ),
          ),
        ),
        //底部留白
        SliverToBoxAdapter(
          child: SizedBox(height: 32),
        ),
      ],
    );
  }
}
