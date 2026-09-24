import 'package:app_translator_web/utils/cookie_helper.dart';
import 'package:flutter/material.dart';
import '../pages/user/login_page.dart';
import '../routes/router_names.dart';

class UserLoginWidget extends StatefulWidget {
  const UserLoginWidget({super.key});

  @override
  State<UserLoginWidget> createState() => _UserLoginWidgetState();
}

class _UserLoginWidgetState extends State<UserLoginWidget> {
  String? _username;

  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
  }

  void _checkLoginStatus() {
    final username = CookieHelper.getCookie('username');
    debugPrint('检查登录状态 - cookie值: $username'); // 调试信息
    // final username = 'admin'; // 仅用来测试
    if (username != null && username.isNotEmpty) {
      setState(() {
        _username = username;
      });
    } else {
      setState(() {
        _username = null;
      });
    }
  }

  void _showLoginPage({bool isRegisterMode = false}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => LoginPage(initialMode: isRegisterMode),
    ).then((_) {
      // 登录页面关闭后重新检查登录状态
      _checkLoginStatus();
    });
  }

  void _showUserProfile() {
    Navigator.pushNamed(context, RouterNames.userInfo);
  }

  void _showIpInfo() {
    Navigator.pushNamed(context, RouterNames.userInfo);
  }

  // // 获取真实IP地址
  // Future<void> _getRealIp() async {
  //   if (_isLoadingIp) return;

  //   setState(() {
  //     _isLoadingIp = true;
  //   });

  //   try {
  //     // 使用多个IP查询服务来获取真实IP
  //     final List<String> ipServices = [
  //       // 'https://api.ipify.org?format=json',
  //       'https://ipapi.co/json/',
  //       // 'https://api.myip.com',
  //       // 'https://ipinfo.io/json',
  //     ];

  //     for (String service in ipServices) {
  //       try {
  //         final response = await html.HttpRequest.getString(service);
  //         final data = json.decode(response);

  //         String? ip;
  //         if (data is Map<String, dynamic>) {
  //           // 根据不同服务的响应格式提取IP
  //           ip = data['ip'] ?? data['query'] ?? data['origin'];
  //         }

  //         if (ip != null && ip.isNotEmpty) {
  //           setState(() {
  //             _realIp = ip;
  //             _isLoadingIp = false;
  //           });
  //           return;
  //         }
  //       } catch (e) {
  //         // 如果当前服务失败，尝试下一个
  //         continue;
  //       }
  //     }

  //     // 如果所有服务都失败，显示错误
  //     setState(() {
  //       _realIp = '获取失败';
  //       _isLoadingIp = false;
  //     });
  //   } catch (e) {
  //     setState(() {
  //       _realIp = '获取失败';
  //       _isLoadingIp = false;
  //     });
  //   }
  // }

  // // 复制IP地址到剪贴板
  // void _copyIpToClipboard() {
  //   if (_realIp != null && _realIp != '获取失败') {
  //     Clipboard.setData(ClipboardData(text: _realIp!));
  //     ScaffoldMessenger.of(context).showSnackBar(
  //       SnackBar(content: Text('已复制IP地址: $_realIp')),
  //     );
  //   }
  // }

  void _logout() {
    // 清除cookie
    CookieHelper.deleteCookie('username');

    setState(() {
      _username = null;
    });

    // 显示退出成功消息
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已退出登录')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_username != null) {
      // 已登录状态
      return PopupMenuButton<String>(
        onSelected: (value) {
          // if (value == 'showIp') {
          //   _getRealIp();
          // } else if (value == 'copyIp') {
          //   _copyIpToClipboard();
          // } else
          if (value == 'profile') {
            _showUserProfile();
          } else if (value == 'logout') {
            _logout();
          }
        },
        itemBuilder: (context) => [
          // PopupMenuItem(
          //   value: 'showIp',
          //   child: Row(
          //     children: [
          //       Icon(
          //         Icons.network_check,
          //         size: 20,
          //         color: Colors.black,
          //       ),
          //       SizedBox(width: 8),
          //       Text(_realIp == null ? '获取IP地址' : 'IP: $_realIp'),
          //       if (_isLoadingIp) ...[
          //         SizedBox(width: 8),
          //         SizedBox(
          //           width: 16,
          //           height: 16,
          //           child: CircularProgressIndicator(
          //             strokeWidth: 2,
          //             valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
          //           ),
          //         ),
          //       ],
          //     ],
          //   ),
          // ),
          // if (_realIp != null && _realIp != '获取失败')
          //   PopupMenuItem(
          //     value: 'copyIp',
          //     child: Row(
          //       children: [
          //         Icon(
          //           Icons.copy,
          //           size: 20,
          //           color: Colors.black,
          //         ),
          //         SizedBox(width: 8),
          //         Text('复制IP地址'),
          //       ],
          //     ),
          //   ),

          const PopupMenuItem(
            value: 'profile',
            child: Row(
              children: [
                Icon(
                  Icons.person_outline,
                  size: 20,
                  color: Colors.black,
                ),
                SizedBox(width: 8),
                Text('用户信息'),
              ],
            ),
          ),
          const PopupMenuItem(
            value: 'logout',
            child: Row(
              children: [
                Icon(
                  Icons.logout,
                  size: 20,
                  color: Colors.black,
                ),
                SizedBox(width: 8),
                Text('退出登录'),
              ],
            ),
          ),
        ],
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.blue.shade100,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.blue.shade300),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.person,
                size: 16,
                color: Colors.blue.shade700,
              ),
              const SizedBox(width: 6),
              Text(
                _username!,
                style: TextStyle(
                  color: Colors.blue.shade700,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.arrow_drop_down,
                size: 16,
                color: Colors.blue.shade700,
              ),
            ],
          ),
        ),
      );
    } else {
      // 未登录状态
      return PopupMenuButton<String>(
        onSelected: (value) {
          if (value == 'ipinfo') {
            _showIpInfo();
          } else if (value == 'login') {
            _showLoginPage();
          } else if (value == 'register') {
            _showLoginPage(isRegisterMode: true);
          }
        },
        itemBuilder: (context) => [
          const PopupMenuItem(
            value: 'ipinfo',
            child: Row(
              children: [
                Icon(
                  Icons.network_check,
                  size: 20,
                  color: Colors.black,
                ),
                SizedBox(width: 8),
                Text('IP信息'),
              ],
            ),
          ),
          const PopupMenuItem(
            value: 'login',
            child: Row(
              children: [
                Icon(
                  Icons.login,
                  size: 20,
                  color: Colors.black,
                ),
                SizedBox(width: 8),
                Text('登录'),
              ],
            ),
          ),
          const PopupMenuItem(
            value: 'register',
            child: Row(
              children: [
                Icon(Icons.person_add, size: 20, color: Colors.black),
                SizedBox(width: 8),
                Text('注册'),
              ],
            ),
          ),
        ],
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.orange.shade100,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.orange.shade300),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.person,
                size: 16,
                color: Colors.orange.shade700,
              ),
              const SizedBox(width: 6),
              Text(
                '登录|注册',
                style: TextStyle(
                  color: Colors.orange.shade700,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.arrow_drop_down,
                size: 16,
                color: Colors.orange.shade700,
              ),
            ],
          ),
        ),
      );
    }
  }
}
