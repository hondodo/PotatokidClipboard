import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:potatokid_clipboard/framework/base/base_stateless_underline_bar_widget.dart';
import 'package:potatokid_clipboard/framework/components/navigations/navigation_widget.dart';
import 'package:potatokid_clipboard/pages/login/controller/login_controller.dart';

class LoginPage extends BaseStatelessUnderlineBarWidget<LoginController> {
  const LoginPage({super.key});

  @override
  String getTitle() {
    return '';
  }

  @override
  PreferredSizeWidget? buildAppBar(BuildContext context) {
    return NavigationWidget(
      title: getTitle(),
      titleWidget: Obx(() {
        return Text(controller.isRegisterMode.value ? '注册'.tr : '登录'.tr);
      }),
      onBack: onBack,
      backgroundColor: barBackgroundColor,
      foregroundColor: barForegroundColor,
      actions: buildActions(),
    );
  }

  @override
  Widget buildBody(BuildContext context) {
    var body = Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Form(
          key: controller.formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 拖拽指示器
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // 标题
              Text(
                controller.isRegisterMode.value ? '用户注册' : '用户登录',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 8),

              Text(
                controller.isRegisterMode.value ? '请填写注册信息' : '请输入您的用户名和密码',
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 32),

              // 用户名输入框
              TextFormField(
                controller: controller.usernameController,
                decoration: InputDecoration(
                  labelText: '用户名',
                  hintText: '请输入用户名',
                  prefixIcon: const Icon(Icons.person_outline),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.blue, width: 2),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '请输入用户名';
                  }
                  if (value.trim().length < 2) {
                    return '用户名至少需要2个字符';
                  }
                  if (value.trim().length > 20) {
                    return '用户名不能超过20个字符';
                  }
                  return null;
                },
                textInputAction: TextInputAction.next,
              ),

              const SizedBox(height: 16),

              // 密码输入框
              TextFormField(
                controller: controller.passwordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: '密码',
                  hintText: '请输入密码',
                  prefixIcon: const Icon(Icons.lock_outline),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.blue, width: 2),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return '请输入密码';
                  }
                  if (value.length < 4) {
                    return '密码至少需要4个字符';
                  }
                  if (value.length > 50) {
                    return '密码不能超过50个字符';
                  }
                  return null;
                },
                textInputAction: controller.isRegisterMode.value
                    ? TextInputAction.next
                    : TextInputAction.done,
                onFieldSubmitted: (_) =>
                    controller.isRegisterMode.value ? null : controller.login(),
              ),

              // 确认密码输入框（仅注册模式显示）
              if (controller.isRegisterMode.value) ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: controller.confirmPasswordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: '确认密码',
                    hintText: '请再次输入密码',
                    prefixIcon: const Icon(Icons.lock_outline),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: Colors.blue, width: 2),
                    ),
                  ),
                  validator: (value) {
                    if (controller.isRegisterMode.value) {
                      if (value == null || value.isEmpty) {
                        return '请确认密码';
                      }
                      if (value != controller.passwordController.text) {
                        return '两次输入的密码不一致';
                      }
                    }
                    return null;
                  },
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => controller.isRegisterMode.value
                      ? controller.register()
                      : controller.login(),
                ),
              ],

              const SizedBox(height: 32),

              // 登录/注册按钮
              ElevatedButton(
                onPressed: controller.isLoading.value
                    ? null
                    : (controller.isRegisterMode.value
                        ? controller.register
                        : controller.login),
                style: ElevatedButton.styleFrom(
                  backgroundColor: controller.isRegisterMode.value
                      ? Colors.green
                      : Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 2,
                ),
                child: controller.isLoading.value
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : Text(
                        controller.isRegisterMode.value ? '注册' : '登录',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),

              const SizedBox(height: 16),

              // 切换登录/注册模式按钮
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: () {
                      // setState(() {
                      controller.isRegisterMode.value =
                          !controller.isRegisterMode.value;
                      controller.confirmPasswordController.clear();
                      // });
                    },
                    child: Text(
                      controller.isRegisterMode.value
                          ? '已有账号？点击登录'
                          : '没有账号？点击注册',
                      style: const TextStyle(
                        color: Colors.blue,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // 取消按钮
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text(
                  '取消',
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: body),
      ],
    );
  }
}
