import 'package:custom_refresh_indicator/custom_refresh_indicator.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:potatokid_clipboard/framework/base/base_stateless_sub_widget.dart';
import 'package:potatokid_clipboard/framework/theme/app_text_theme.dart';
import 'package:potatokid_clipboard/pages/home/tabs/me/vm/me_controller.dart';
import 'package:potatokid_clipboard/utils/device_utils.dart';
import 'package:potatokid_clipboard/utils/dialog_helper.dart';

class MePage extends BaseStatelessSubWidget<MeController> {
  const MePage({super.key});

  @override
  Widget buildBody(BuildContext context) {
    return CustomMaterialIndicator(
      onRefresh: () async {
        await controller.onRefresh();
      },
      scrollableBuilder: (context, child, controller) {
        // 在 Windows 平台上启用鼠标拖动滚动
        return ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(
            dragDevices: {
              PointerDeviceKind.mouse,
              PointerDeviceKind.touch,
              PointerDeviceKind.stylus,
              PointerDeviceKind.trackpad,
            },
          ),
          child: child,
        );
      },
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: buildMeInfo(),
            ),
          ),
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.only(
                  top: 0, left: 16, right: 16, bottom: 12),
              child: buildIpInfo(),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildMeInfo() {
    if (controller.user.value.isEmpty) {
      return const SizedBox.shrink();
    }
    return Row(
      children: [
        const Icon(Icons.person, size: 32, color: AppTextTheme.hintColor),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(controller.user.value.name ?? '',
                style: AppTextTheme.textStyle.body),
            const SizedBox(width: 4),
            Text('Id: ${controller.user.value.id ?? ''}',
                style: AppTextTheme.textStyle.hint),
          ],
        ),
      ],
    );
  }

  Widget buildIpInfo() {
    Widget column = Column(children: [
      if (controller.ipInfoModel.value != null) ...[
        _buildInfoCard(
          '设备ID',
          DeviceUtils.instance.deviceId,
          Icons.device_hub,
          copyable: true,
        ),
        _buildInfoCard(
          'IP地址',
          controller.ipInfoModel.value?.ip,
          Icons.network_check,
          copyable: true,
        ),
        _buildInfoCard(
          '城市',
          controller.ipInfoModel.value?.city,
          Icons.location_city,
          copyable: true,
        ),
        _buildInfoCard(
          '地区',
          controller.ipInfoModel.value?.region,
          Icons.place,
          copyable: true,
        ),
        _buildInfoCard(
          '国家',
          controller.ipInfoModel.value?.countryName,
          Icons.public,
          copyable: true,
        ),
        _buildInfoCard(
          '国家代码',
          controller.ipInfoModel.value?.countryCode,
          Icons.flag,
          copyable: true,
        ),
        _buildInfoCard(
          '时区',
          controller.ipInfoModel.value?.timezone,
          Icons.access_time,
          copyable: true,
        ),
        _buildInfoCard(
          'ISP',
          controller.ipInfoModel.value?.org,
          Icons.business,
          copyable: true,
        ),
        _buildInfoCard(
          '纬度',
          '${controller.ipInfoModel.value?.latitude ?? '--'}',
          Icons.my_location,
          copyable: true,
        ),
        _buildInfoCard(
          '经度',
          '${controller.ipInfoModel.value?.longitude ?? '--'}',
          Icons.my_location,
          copyable: true,
        ),
      ] else ...[
        _buildInfoCard(
          '设备ID',
          DeviceUtils.instance.deviceId,
          Icons.device_hub,
          copyable: true,
        ),
        // 位置信息不可用时的提示
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                const Icon(Icons.location_off, size: 48, color: Colors.grey),
                const SizedBox(height: 8),
                const Text(
                  '位置信息不可用',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  '可能原因：网络限制或外部API不可用',
                  style: TextStyle(color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: controller.loadIpInfo,
                  icon: const Icon(Icons.refresh),
                  label: const Text('尝试获取位置信息'),
                ),
              ],
            ),
          ),
        ),
      ],
    ]);
    return column;
  }

  Widget _buildInfoCard(String title, String? value, IconData icon,
      {bool copyable = true}) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: Colors.blue),
        title: Text(title, style: AppTextTheme.textStyle.body),
        subtitle: Text(value ?? '未知', style: AppTextTheme.textStyle.hint),
        trailing: copyable && value != null
            ? IconButton(
                icon: const Icon(Icons.copy, size: 20),
                onPressed: () => _copyToClipboard(value, title),
              )
            : null,
      ),
    );
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    DialogHelper.showTextToast('已复制$label: $text');
  }
}
