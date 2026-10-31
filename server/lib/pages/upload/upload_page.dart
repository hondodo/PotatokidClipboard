import 'package:flutter/material.dart';
import 'package:app_translator_web/pages/upload/widget/upload_page_content.dart';
import 'package:app_translator_web/components/user_login_widget.dart';
import 'package:app_translator_web/utils/cookie_helper.dart';

class UploadPage extends StatefulWidget {
  const UploadPage({super.key});

  @override
  State<UploadPage> createState() => _UploadPageState();
}

class _UploadPageState extends State<UploadPage> {
  String? _username;

  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
  }

  void _checkLoginStatus() {
    final username = CookieHelper.getCookie('username');
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('上传文件'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 16.0),
            child: UserLoginWidget(),
          ),
        ],
      ),
      body: _username != null
          ? const UploadPageContent()
          : _buildLoginRequiredWidget(),
    );
  }

  Widget _buildLoginRequiredWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.lock_outline,
            size: 80,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 24),
          Text(
            '需要登录才能上传文件',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '请先登录您的账户，然后就可以上传和管理您的个人文件了',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade500,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          const UserLoginWidget(),
        ],
      ),
    );
  }
}
