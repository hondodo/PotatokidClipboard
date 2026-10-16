import 'package:flutter/material.dart';
import 'package:pscreen_control/app/di/injection.dart';
import 'package:pscreen_control/app/storage/app_settings.dart';
import 'package:pscreen_control/app/utils/app_log.dart';
import 'package:pscreen_control/core/nim_client.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppSettings.instance.ensureLoaded();
  await Injection.init();
  // NIM 初始化失败不阻断 UI：设置页可见并显示错误（Task 2）。
  try {
    await getIt<NimClient>().init();
    final String account = AppSettings.instance.nimAccount;
    if (account.isNotEmpty) {
      await getIt<NimClient>().autoLogin(account: account);
    }
  } catch (e) {
    AppLog.e('NIM init/autoLogin failed: $e');
  }
  runApp(const PscreenControlApp());
}

class PscreenControlApp extends StatelessWidget {
  const PscreenControlApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PScreen Control',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      // Task 2 will swap in the real SettingsPage.
      home: const Scaffold(body: Center(child: Text('PScreen Control'))),
    );
  }
}
