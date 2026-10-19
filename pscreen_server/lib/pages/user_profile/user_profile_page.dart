// import 'package:flutter/material.dart';
// import 'widget/user_profile_content.dart';

// class UserProfilePage extends StatefulWidget {
//   const UserProfilePage({super.key});

//   @override
//   State<UserProfilePage> createState() => _UserProfilePageState();
// }

// class _UserProfilePageState extends State<UserProfilePage> {
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: const Text('用户信息'),
//         backgroundColor: Colors.blue.shade50,
//         elevation: 0,
//       ),
//       body: const UserProfileContent(),
//     );
//   }
// }

import 'package:app_translator_web/framework/base/base_stateless_underline_bar_widget.dart';
import 'package:app_translator_web/pages/user_profile/vm/user_profile_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

class UserProfilePage
    extends BaseStatelessUnderlineBarWidget<UserProfileController> {
  const UserProfilePage({super.key});

  @override
  Widget buildBody(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          // 基本用户信息
          _buildInfoCard(
            '用户名',
            controller.username.value,
            Icons.person,
            copyable: true,
          ),

          // 位置信息部分
          if (controller.locationData.value != null) ...[
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                '位置信息',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
            ),
            _buildInfoCard(
              'IP地址',
              controller.locationData.value?.ip,
              Icons.network_check,
              copyable: true,
            ),
            _buildInfoCard(
              '城市',
              controller.locationData.value?.city,
              Icons.location_city,
              copyable: true,
            ),
            _buildInfoCard(
              '地区',
              controller.locationData.value?.region,
              Icons.place,
              copyable: true,
            ),
            _buildInfoCard(
              '国家',
              controller.locationData.value?.countryName,
              Icons.public,
              copyable: true,
            ),
            _buildInfoCard(
              '国家代码',
              controller.locationData.value?.countryCode,
              Icons.flag,
              copyable: true,
            ),
            _buildInfoCard(
              '时区',
              controller.locationData.value?.timezone,
              Icons.access_time,
              copyable: true,
            ),
            _buildInfoCard(
              'ISP',
              controller.locationData.value?.org,
              Icons.business,
              copyable: true,
            ),
            _buildInfoCard(
              '纬度',
              '${controller.locationData.value?.latitude ?? '--'}',
              Icons.my_location,
              copyable: true,
            ),
            _buildInfoCard(
              '经度',
              '${controller.locationData.value?.longitude ?? '--'}',
              Icons.my_location,
              copyable: true,
            ),
          ] else ...[
            // 位置信息不可用时的提示
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    const Icon(Icons.location_off,
                        size: 48, color: Colors.grey),
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
                      onPressed: controller.getIpInfo,
                      icon: const Icon(Icons.refresh),
                      label: const Text('尝试获取位置信息'),
                    ),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  @override
  String getTitle() {
    return '用户信息';
  }

  Widget _buildInfoCard(String title, String? value, IconData icon,
      {bool copyable = true}) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListTile(
        leading: Icon(icon, color: Colors.blue),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(value ?? '未知'),
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
    ScaffoldMessenger.of(Get.context!).showSnackBar(
      SnackBar(content: Text('已复制$label: $text')),
    );
  }
}
