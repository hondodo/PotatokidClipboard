import 'package:app_translator_web/pages/note/widget/note_page_content.dart';
import 'package:flutter/material.dart';
import 'package:app_translator_web/components/user_login_widget.dart';
import 'package:app_translator_web/utils/cookie_helper.dart';

class NotePage extends StatefulWidget {
  const NotePage({super.key});

  @override
  State<NotePage> createState() => _NotePageState();
}

class _NotePageState extends State<NotePage> {
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
        title: const Text('笔记管理'),
        backgroundColor: Colors.purple,
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
          ? const NotePageContent()
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
            '需要登录才能管理笔记',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '请先登录您的账户，然后就可以创建和管理您的个人笔记了',
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
