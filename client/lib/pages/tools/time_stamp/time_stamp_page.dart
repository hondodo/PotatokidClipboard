import 'package:flutter/material.dart';
import 'package:get/get_utils/get_utils.dart';
import 'package:potatokid_clipboard/app/app_enums.dart';
import 'package:potatokid_clipboard/framework/base/base_stateless_sub_widget.dart';
import 'package:potatokid_clipboard/framework/components/app_button.dart';
import 'package:potatokid_clipboard/framework/theme/app_text_theme.dart';
import 'package:potatokid_clipboard/pages/tools/time_stamp/vm/time_stamp_controller.dart';

class TimeStampPage extends BaseStatelessSubWidget<TimeStampController> {
  const TimeStampPage({super.key});

  @override
  Widget buildBody(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
            ),
            child: Text(
              '当前时间戳'.tr,
              style: AppTextTheme.textStyle.subtitle,
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(
              left: 16,
              right: 16,
              top: 8,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  onEnter: (event) {
                    controller.isHoverTimeStamp.value = true;
                  },
                  onExit: (event) {
                    controller.isHoverTimeStamp.value = false;
                  },
                  child: GestureDetector(
                    onTap: () {
                      controller.onCurrentTimeStampClick();
                    },
                    child: Text(
                      '@value'.trParams(
                        {
                          'value': (controller.timeStampUnit.value ==
                                      TimeStampUnit.second
                                  ? controller.currentTimeStamp.value ~/ 1000
                                  : controller.currentTimeStamp.value)
                              .toString(),
                        },
                      ),
                      style: AppTextTheme.textStyle.title.bold.setColor(
                        controller.isHoverTimeStamp.value
                            ? AppTextTheme.primaryColor
                            : AppTextTheme.textColor,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 4),
                Text(
                  controller.timeStampUnit.value.text,
                  style: AppTextTheme.textStyle.body,
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(
              left: 16,
              right: 16,
              top: 8,
            ),
            child: Row(
              children: [
                // 带图标和文字的按钮 -  切换单位（秒/毫秒切换）
                AppButton.outlined(
                  onPressed: () {
                    controller.onTimeStampUnitChange();
                  },
                  child: Row(
                    children: [
                      Icon(Icons.access_time),
                      SizedBox(width: 4),
                      Text('切换单位'.tr, style: AppTextTheme.textStyle.body),
                    ],
                  ),
                ),
                SizedBox(width: 8),
                AppButton.outlined(
                  onPressed: () {
                    controller.onCopy();
                  },
                  child: Row(
                    children: [
                      Icon(Icons.copy),
                      SizedBox(width: 4),
                      Text('复制'.tr, style: AppTextTheme.textStyle.body),
                    ],
                  ),
                ),
                SizedBox(width: 8),
                AppButton.outlined(
                  onPressed: () {
                    controller.onStopOrStart();
                  },
                  child: Row(
                    children: [
                      Icon(controller.isTimerRunning.value
                          ? Icons.stop
                          : Icons.play_arrow),
                      SizedBox(width: 4),
                      Text(controller.isTimerRunning.value ? '停止'.tr : '开始'.tr,
                          style: AppTextTheme.textStyle.body),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
            ),
            child: Divider(
              color: AppTextTheme.hintColor,
              height: 1,
              thickness: 1,
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.access_time,
                  size: AppTextTheme.textStyle.subtitle.fontSize,
                ),
                SizedBox(width: 4),
                Text('时间戳转日期时间'.tr, style: AppTextTheme.textStyle.subtitle),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(
              left: 16,
              right: 16,
              top: 8,
            ),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                SizedBox(
                  width: 156,
                  height: 40,
                  child: TextField(
                    controller:
                        controller.timestamp2DateTimeTimestampController,
                    style: AppTextTheme.textStyle.body,
                    decoration: InputDecoration(
                      hintText: '请输入时间戳'.tr,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                // popup菜单 秒/毫秒
                // 显示当前选中单位
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue),
                  ),
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  width: 72,
                  height: 40,
                  child: PopupMenuButton(
                    elevation: 4,
                    offset: Offset(0, 10),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        controller.timestamp2DateTimeUnit.value.textWithUnit,
                        style:
                            AppTextTheme.textStyle.body.setColor(Colors.blue),
                        textAlign: TextAlign.left,
                      ),
                    ),
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        child: Text(
                          TimeStampUnit.second.textWithUnit,
                          style: AppTextTheme.textStyle.body,
                        ),
                        onTap: () {
                          controller.onDateTimeToTimeStampTimeStampUnitChange(
                              TimeStampUnit.second);
                        },
                      ),
                      PopupMenuItem(
                        child: Text(
                          TimeStampUnit.millisecond.textWithUnit,
                          style: AppTextTheme.textStyle.body,
                        ),
                        onTap: () {
                          controller.onDateTimeToTimeStampTimeStampUnitChange(
                              TimeStampUnit.millisecond);
                        },
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 64,
                  height: 40,
                  child: AppButton.outlined(
                    onPressed: () {
                      controller.onTimeStampToDateTime();
                    },
                    child: Text('转换'.tr, style: AppTextTheme.textStyle.body),
                  ),
                ),
                // popup菜单 秒/毫秒
                // 显示所有时区列表
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue),
                  ),
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  width: 308,
                  height: 40,
                  child: PopupMenuButton(
                    elevation: 4,
                    offset: Offset(0, 10),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '@name (@offset)'.trParams({
                          'name': controller.selectedTimeZone.value?.name ?? '',
                          'offset':
                              controller.selectedTimeZone.value?.offsetText ??
                                  '',
                        }),
                        style:
                            AppTextTheme.textStyle.body.setColor(Colors.blue),
                        textAlign: TextAlign.left,
                      ),
                    ),
                    itemBuilder: (context) => controller.timeZoneList
                        .map((e) => PopupMenuItem(
                              child: Text(
                                  '@name (@offset)'.trParams({
                                    'name': e.name,
                                    'offset': e.offsetText,
                                  }),
                                  style: AppTextTheme.textStyle.body),
                              onTap: () {
                                controller.onTimeZoneChange(e);
                              },
                            ))
                        .toList(),
                  ),
                ),
                SizedBox(
                  width: 308,
                  height: 40,
                  child: TextField(
                    controller: controller.timestamp2DateTimeFormatController,
                    style: AppTextTheme.textStyle.body,
                    decoration: InputDecoration(
                      hintText: '请输入日期时间格式'.tr,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                SizedBox(
                  width: 308,
                  height: 40,
                  child: TextField(
                    controller: controller.timestamp2DateTimeDateTimeController,
                    style: AppTextTheme.textStyle.body,
                    decoration: InputDecoration(
                      hintText: '请输入日期时间'.tr,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
            ),
            child: Divider(
              color: AppTextTheme.hintColor,
              height: 1,
              thickness: 1,
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.date_range,
                  size: AppTextTheme.textStyle.subtitle.fontSize,
                ),
                SizedBox(width: 4),
                Text('日期时间转时间戳'.tr, style: AppTextTheme.textStyle.subtitle),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(
              left: 16,
              right: 16,
              top: 8,
            ),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                SizedBox(
                  width: 228,
                  height: 40,
                  child: TextField(
                    controller:
                        controller.dateTimeToTimeStampDateTimeController,
                    style: AppTextTheme.textStyle.body,
                    decoration: InputDecoration(
                      hintText: '请输入日期时间'.tr,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                // popup菜单 秒/毫秒
                // 显示当前选中单位
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue),
                  ),
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  width: 72,
                  height: 40,
                  child: PopupMenuButton(
                    elevation: 4,
                    offset: Offset(0, 10),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        controller.dateTimeToTimeStampUnit.value.textWithUnit,
                        style:
                            AppTextTheme.textStyle.body.setColor(Colors.blue),
                        textAlign: TextAlign.left,
                      ),
                    ),
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        child: Text(
                          TimeStampUnit.second.textWithUnit,
                          style: AppTextTheme.textStyle.body,
                        ),
                        onTap: () {
                          controller.onDateTimeToTimeStampUnitChange(
                              TimeStampUnit.second);
                        },
                      ),
                      PopupMenuItem(
                        child: Text(
                          TimeStampUnit.millisecond.textWithUnit,
                          style: AppTextTheme.textStyle.body,
                        ),
                        onTap: () {
                          controller.onDateTimeToTimeStampUnitChange(
                              TimeStampUnit.millisecond);
                        },
                      ),
                    ],
                  ),
                ),
                // popup菜单 秒/毫秒
                // 显示所有时区列表
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue),
                  ),
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  width: 228,
                  height: 40,
                  child: PopupMenuButton(
                    elevation: 4,
                    offset: Offset(0, 10),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '@name (@offset)'.trParams({
                          'name': controller
                                  .selectedDateTimeToTimeZone.value?.name ??
                              '',
                          'offset': controller.selectedDateTimeToTimeZone.value
                                  ?.offsetText ??
                              '',
                        }),
                        style:
                            AppTextTheme.textStyle.body.setColor(Colors.blue),
                        textAlign: TextAlign.left,
                      ),
                    ),
                    itemBuilder: (context) => controller.timeZoneList
                        .map((e) => PopupMenuItem(
                              child: Text(
                                  '@name (@offset)'.trParams({
                                    'name': e.name,
                                    'offset': e.offsetText,
                                  }),
                                  style: AppTextTheme.textStyle.body),
                              onTap: () {
                                controller.onDateTimeToTimeZoneChange(e);
                              },
                            ))
                        .toList(),
                  ),
                ),
                SizedBox(
                  width: 72,
                  height: 40,
                  child: AppButton.outlined(
                    onPressed: () {
                      controller.onDateTimeToTimeStamp();
                    },
                    child: Text('转换'.tr, style: AppTextTheme.textStyle.body),
                  ),
                ),
                SizedBox(
                  width: 308,
                  height: 40,
                  child: TextField(
                    controller:
                        controller.dateTimeToTimeStampTimestampController,
                    style: AppTextTheme.textStyle.body,
                    decoration: InputDecoration(
                      hintText: '请输入时间戳'.tr,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // 底部留白
        SliverToBoxAdapter(
          child: SizedBox(height: 16),
        ),
      ],
    );
  }
}
