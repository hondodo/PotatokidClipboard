import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:potatokid_clipboard/components/battery_widgets/vm/battery_controller.dart';
import 'package:potatokid_clipboard/framework/theme/app_text_theme.dart';

class BatteryIconTextWidget extends StatelessWidget {
  const BatteryIconTextWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.put(BatteryController());
    return Obx(
      () => Row(
        children: [
          Icon(c.batteryState.value?.icon ?? Icons.battery_alert),
          Text(
            c.batteryState.value?.text ?? '未识别'.tr,
            style: AppTextTheme.textStyle.body,
          ),
          Text(
            '${c.batteryLevel.value}%',
            style: AppTextTheme.textStyle.body,
          ),
        ],
      ),
    );
  }
}
