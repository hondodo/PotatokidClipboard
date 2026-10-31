import 'package:app_translator_web/app/app_const.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:convert';
import 'dart:async';
import '../../../utils/cookie_helper.dart';
import '../../../apis.dart';

class UserProfileContent extends StatefulWidget {
  const UserProfileContent({super.key});

  @override
  State<UserProfileContent> createState() => _UserProfileContentState();
}

class _UserProfileContentState extends State<UserProfileContent> {
  String? _username;
  Map<String, dynamic>? _locationData;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  void _loadUserData() async {
    // 获取用户名
    final username = CookieHelper.getCookie('username');
    setState(() {
      _username = username;
    });

    // 可选：获取地理位置信息（可能失败）
    try {
      await _getLocationData();
    } catch (e) {
      print('位置信息获取失败，但不影响基本功能: $e');
    }
  }

  Future<void> _getLocationData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 使用代理API请求位置信息
      final request = html.HttpRequest();
      request.open('GET', Apis.getIpInfoUrl);
      request.send();

      await request.onLoad.first;

      if (request.status == 200) {
        final responseData = json.decode(request.responseText!);

        // 检查代理API响应
        if (responseData[AppConst.CODE] == AppConst.CODE_SUCCESS &&
            responseData[AppConst.DATA] != null) {
          setState(() {
            _locationData = responseData['data'];
            _isLoading = false;
          });
          debugPrint('位置信息获取成功: ${_locationData?['ip']}');
        } else {
          throw Exception(responseData['message'] ?? '获取位置信息失败');
        }
      } else {
        throw Exception('HTTP错误: ${request.status}');
      }
    } catch (e) {
      debugPrint('获取位置信息失败: $e'); // 调试信息

      setState(() {
        _errorMessage =
            '获取位置信息失败: ${e.toString()}\n\n可能原因：\n1. 网络连接问题\n2. 代理服务不可用\n3. 外部API服务限制';
        _isLoading = false;
      });
    }
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已复制$label: $text')),
    );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('正在获取用户信息...'),
                ],
              ),
            )
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error, size: 64, color: Colors.red),
                      const SizedBox(height: 16),
                      Text(_errorMessage!, textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _getLocationData,
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 16),
                      // 基本用户信息
                      _buildInfoCard(
                        '用户名',
                        _username,
                        Icons.person,
                        copyable: true,
                      ),

                      // 位置信息部分
                      if (_locationData != null) ...[
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
                          _locationData?['ip'],
                          Icons.network_check,
                          copyable: true,
                        ),
                        _buildInfoCard(
                          '城市',
                          _locationData?['city'],
                          Icons.location_city,
                          copyable: true,
                        ),
                        _buildInfoCard(
                          '地区',
                          _locationData?['region'],
                          Icons.place,
                          copyable: true,
                        ),
                        _buildInfoCard(
                          '国家',
                          _locationData?['country_name'],
                          Icons.public,
                          copyable: true,
                        ),
                        _buildInfoCard(
                          '国家代码',
                          _locationData?['country_code'],
                          Icons.flag,
                          copyable: true,
                        ),
                        _buildInfoCard(
                          '时区',
                          _locationData?['timezone'],
                          Icons.access_time,
                          copyable: true,
                        ),
                        _buildInfoCard(
                          'ISP',
                          _locationData?['org'],
                          Icons.business,
                          copyable: true,
                        ),
                        _buildInfoCard(
                          '纬度',
                          _locationData?['latitude']?.toString(),
                          Icons.my_location,
                          copyable: true,
                        ),
                        _buildInfoCard(
                          '经度',
                          _locationData?['longitude']?.toString(),
                          Icons.my_location,
                          copyable: true,
                        ),
                      ] else ...[
                        // 位置信息不可用时的提示
                        Card(
                          margin: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
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
                                  onPressed: _getLocationData,
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
                ),
    );
  }
}
