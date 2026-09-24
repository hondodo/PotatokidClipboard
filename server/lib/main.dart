import 'package:app_translator_web/pages/home/home_page.dart';
import 'package:app_translator_web/routes/router_names.dart';
import 'package:app_translator_web/routes/routers_manager.dart';
import 'package:flutter/material.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:get/get.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 设置URL策略，去掉#符号
  usePathUrlStrategy();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: '薯仔工具箱',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      // 设置初始路由
      initialRoute: RouterNames.root,
      // 配置路由
      routes: RouterManager.routes,
      // getPages: RouterManager.pages,  // 使用getPages会出现按下F5刷新页面时，页面会重新加载，导致页面状态丢失
      // 处理未知路由
      onUnknownRoute: (settings) {
        return MaterialPageRoute(
          builder: (context) => const HomePage(),
        );
      },
    );
  }
}
