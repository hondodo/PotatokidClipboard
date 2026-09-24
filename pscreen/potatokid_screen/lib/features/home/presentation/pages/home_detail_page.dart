import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:potatokid_screen/core/di/injection.dart';
import 'package:potatokid_screen/core/router/app_router.dart';
import 'package:potatokid_screen/core/router/route_params.dart';

/// 首页详情页：通过 [HomeDetailParams] 接收类型安全参数。
class HomeDetailPage extends StatelessWidget {
  const HomeDetailPage({super.key, required this.params});

  final HomeDetailParams params;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(params.title ?? 'home_detail_title'.tr())),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('id: ${params.id ?? '-'}'),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Injection.get<AppRouter>().pop(),
              child: Text('action_back'.tr()),
            ),
          ],
        ),
      ),
    );
  }
}
