import 'package:flutter/material.dart';
import 'package:pscreen_home/core/di/injection.dart';
import 'package:pscreen_home/core/router/app_router.dart';

/// 应用根组件：MaterialApp.router + GoRouter 路由配置。
/// 中控屏场景固定使用暗色主题。
class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    final AppRouter appRouter = Injection.get<AppRouter>();
    return MaterialApp.router(
      title: '中控台',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      routerConfig: appRouter.router,
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final bool dark = brightness == Brightness.dark;
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF4F8CFF),
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor:
          dark ? const Color(0xFF0E1116) : const Color(0xFFF5F7FA),
      appBarTheme: AppBarTheme(
        backgroundColor: dark ? const Color(0xFF0E1116) : const Color(0xFFF5F7FA),
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    );
  }
}
