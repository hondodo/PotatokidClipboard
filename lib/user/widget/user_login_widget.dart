import 'package:flutter/material.dart';
import 'package:potatokid_clipboard/framework/base/base_stateless_sub_widget.dart';
import 'package:potatokid_clipboard/user/controller/user_controller.dart';

class UserLoginWidget extends BaseStatelessSubWidget<UserController> {
  const UserLoginWidget({super.key})
      : super(bodyBackgroundColor: Colors.transparent);

  @override
  Widget buildBody(BuildContext context) {
    if (controller.user.value.id != null) {
      // 已登录状态
      return PopupMenuButton<String>(
        onSelected: (value) {
          if (value == 'profile') {
            controller.showUserProfile();
          } else if (value == 'logout') {
            controller.logout();
          }
        },
        itemBuilder: (context) => [
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
                controller.user.value.name ?? '',
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
            controller.showIpInfo();
          } else if (value == 'login') {
            controller.showLoginPage();
          } else if (value == 'register') {
            controller.showLoginPage(isRegisterMode: true);
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
