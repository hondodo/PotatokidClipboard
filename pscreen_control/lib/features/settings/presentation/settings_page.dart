import 'package:flutter/material.dart';
import 'package:pscreen_control/app/config/app_config.dart';
import 'package:pscreen_control/app/di/injection.dart';
import 'package:pscreen_control/app/storage/app_settings.dart';
import 'package:pscreen_control/core/nim_client.dart';
import 'package:pscreen_control/features/send/presentation/send_page.dart';

/// 设置页：账号 + token 登录；成功后进入发送端主页。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _account =
      TextEditingController(text: AppSettings.instance.nimAccount);
  late final TextEditingController _token =
      TextEditingController(text: AppSettings.instance.nimToken);
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _account.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final bool ok = await getIt<NimClient>().login(
      account: _account.text.trim(),
      token: _token.text.trim().isEmpty
          ? AppConfig.defaultNimToken
          : _token.text.trim(),
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = ok ? null : '登录失败，请检查账号/token';
    });
    if (ok) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const SendPage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            TextField(
              controller: _account,
              decoration: const InputDecoration(labelText: '云信账号'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _token,
              decoration: InputDecoration(
                labelText: 'Token（默认 ${AppConfig.defaultNimToken}）',
              ),
            ),
            const SizedBox(height: 24),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy ? null : _login,
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('登录'),
            ),
          ],
        ),
      ),
    );
  }
}
