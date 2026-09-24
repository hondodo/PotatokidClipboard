import 'package:flutter/material.dart';
import 'package:get/get_utils/src/extensions/internacionalization.dart';
import 'package:potatokid_clipboard/components/app_text_field.dart';
import 'package:potatokid_clipboard/framework/base/base_stateless_sub_widget.dart';
import 'package:potatokid_clipboard/framework/theme/app_text_theme.dart';
import 'package:potatokid_clipboard/pages/tools/search_web/widget/vm/search_bar_controller.dart';

class SearchBarWidget extends BaseStatelessSubWidget<SearchBarController> {
  const SearchBarWidget({super.key, super.controllerTag});

  @override
  Widget buildBody(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text('搜索方式'.tr, style: AppTextTheme.textStyle.body),
        SizedBox(width: 8),
        PopupMenuButton(
          elevation: 4,
          offset: Offset(0, 10),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                Image.network(controller.selectedSearchProvider.value.icon,
                    width: 16, height: 16),
                SizedBox(width: 2),
                Text(
                  controller.selectedSearchProvider.value.name,
                  style: AppTextTheme.textStyle.body.setColor(Colors.blue),
                  textAlign: TextAlign.left,
                ),
              ],
            ),
          ),
          itemBuilder: (context) => controller.searchProviders
              .map(
                (e) => PopupMenuItem(
                  child: Row(
                    children: [
                      Image.network(e.icon, width: 16, height: 16),
                      SizedBox(width: 2),
                      Text(e.name, style: AppTextTheme.textStyle.body),
                    ],
                  ),
                  onTap: () {
                    controller.onSearchProviderChanged(e);
                  },
                ),
              )
              .toList(),
        ),
        SizedBox(width: 8),
        Text('附加参数'.tr, style: AppTextTheme.textStyle.body),
        SizedBox(width: 2),
        Expanded(
          child: AppTextField(
            controller: controller.searchNowTailController,
            hintText: '附加参数'.tr,
          ),
        ),
      ],
    );
  }
}
