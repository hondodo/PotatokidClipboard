import 'package:app_translator_web/app/app_const.dart';
import 'package:app_translator_web/utils/string_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:html' as html;
import '../../apis.dart';
import '../../utils/cookie_helper.dart';

class LoginPage extends StatefulWidget {
  final bool initialMode;

  const LoginPage({super.key, this.initialMode = false});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;
  late bool _isRegisterMode;

  @override
  void initState() {
    super.initState();
    _isRegisterMode = widget.initialMode;
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final response = await html.HttpRequest.request(
        Apis.register,
        method: 'POST',
        requestHeaders: {
          'Content-Type': 'application/json',
        },
        sendData: jsonEncode({
          'username': _usernameController.text.trim(),
          'password': _passwordController.text.toMd5,
        }),
      );

      if (response.status == 200) {
        final responseData = jsonDecode(response.responseText!);
        if (responseData[AppConst.CODE] == AppConst.CODE_SUCCESS) {
          // 注册成功，切换到登录模式
          setState(() {
            _isRegisterMode = false;
            _confirmPasswordController.clear();
          });
          if (mounted) {
            // 显示成功消息
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('注册成功！请登录'),
                backgroundColor: Colors.green,
              ),
            );
          }
        } else {
          // 注册失败
          _showErrorDialog(responseData[AppConst.MSG] ?? '注册失败');
        }
      } else {
        _showErrorDialog('服务器错误，请稍后重试');
      }
    } catch (e) {
      _showErrorDialog('网络错误，请检查网络连接');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final response = await html.HttpRequest.request(
        Apis.login,
        method: 'POST',
        requestHeaders: {
          'Content-Type': 'application/json',
        },
        sendData: jsonEncode({
          'username': _usernameController.text.trim(),
          'password': _passwordController.text.toMd5,
        }),
      );

      if (response.status == 200) {
        final responseData = jsonDecode(response.responseText!);
        if (responseData[AppConst.CODE] == AppConst.CODE_SUCCESS) {
          // 登录成功，检查服务端设置的cookie
          final username = _usernameController.text.trim();

          // 立即检查cookie（服务端应该已经设置）
          final cookieValue = CookieHelper.getCookie('username');
          debugPrint('登录后cookie值: $cookieValue'); // 调试信息

          // 如果服务端cookie设置失败，则客户端设置（备用方案）
          if (cookieValue == null || cookieValue.isEmpty) {
            debugPrint('服务端cookie设置失败，使用客户端设置');
            CookieHelper.setCookie('username', username,
                maxAge: 14 * 24 * 60 * 60);
          }

          if (mounted) {
            // 关闭页面
            Navigator.of(context).pop();

            // 显示成功消息
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('欢迎回来，$username！'),
                backgroundColor: Colors.green,
              ),
            );
          }
        } else {
          // 登录失败
          _showErrorDialog(responseData[AppConst.MSG] ?? '登录失败');
        }
      } else {
        _showErrorDialog('服务器错误，请稍后重试');
      }
    } catch (e) {
      _showErrorDialog('网络错误，请检查网络连接');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('登录失败'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
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
          key: _formKey,
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
                _isRegisterMode ? '用户注册' : '用户登录',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 8),

              Text(
                _isRegisterMode ? '请填写注册信息' : '请输入您的用户名和密码',
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 32),

              // 用户名输入框
              TextFormField(
                controller: _usernameController,
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
                controller: _passwordController,
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
                textInputAction: _isRegisterMode
                    ? TextInputAction.next
                    : TextInputAction.done,
                onFieldSubmitted: (_) => _isRegisterMode ? null : _login(),
              ),

              // 确认密码输入框（仅注册模式显示）
              if (_isRegisterMode) ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: _confirmPasswordController,
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
                    if (_isRegisterMode) {
                      if (value == null || value.isEmpty) {
                        return '请确认密码';
                      }
                      if (value != _passwordController.text) {
                        return '两次输入的密码不一致';
                      }
                    }
                    return null;
                  },
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) =>
                      _isRegisterMode ? _register() : _login(),
                ),
              ],

              const SizedBox(height: 32),

              // 登录/注册按钮
              ElevatedButton(
                onPressed:
                    _isLoading ? null : (_isRegisterMode ? _register : _login),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isRegisterMode ? Colors.green : Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 2,
                ),
                child: _isLoading
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
                        _isRegisterMode ? '注册' : '登录',
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
                      setState(() {
                        _isRegisterMode = !_isRegisterMode;
                        _confirmPasswordController.clear();
                      });
                    },
                    child: Text(
                      _isRegisterMode ? '已有账号？点击登录' : '没有账号？点击注册',
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
  }
}
