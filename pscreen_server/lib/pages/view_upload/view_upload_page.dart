import 'package:app_translator_web/pages/view_upload/widget/view_upload_page_content.dart';
import 'package:flutter/material.dart';
import 'package:app_translator_web/components/user_login_widget.dart';
import 'package:app_translator_web/utils/cookie_helper.dart';

class ViewUploadPage extends StatefulWidget {
  const ViewUploadPage({super.key});

  @override
  State<ViewUploadPage> createState() => _ViewUploadPageState();
}

class _ViewUploadPageState extends State<ViewUploadPage> {
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
        title: const Text('文件管理'),
        backgroundColor: Colors.green,
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
      body: ViewUploadPageContent(isGuest: _username == null),
    );
  }
}
