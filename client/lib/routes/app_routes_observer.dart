import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:potatokid_clipboard/framework/utils/app_log.dart';

// app路由监听
class AppRoutesObserver extends RouteObserver {
  static AppRoutesObserver? _instance;
  static AppRoutesObserver get instance => _instance ??= AppRoutesObserver._();
  AppRoutesObserver._() {
    // ignore: avoid_print
    print('AppRoutesObserver initialized');
  }

  // 用于通知路由变化，主要用于页面返回后，通知页面刷新
  StreamController<MapEntry<String, dynamic>> afterBackRouteStreamController =
      StreamController<MapEntry<String, dynamic>>.broadcast();

  final List<Route> _appRoutes = [];

  bool containsRoute(String routeName) {
    return _appRoutes.any((route) => route.settings.name == routeName);
  }

  @override
  void didPush(Route route, Route? previousRoute) {
    Log.d('[AppRoutesObserver] didPush: ${route.settings.name}');
    super.didPush(route, previousRoute);
    _appRoutes.insert(0, route);
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    Log.d('[AppRoutesObserver] didPop: ${route.settings.name}');
    super.didPop(route, previousRoute);
    _appRoutes.remove(route);
    try {
      afterBackRouteStreamController.add(MapEntry(
        previousRoute?.settings.name ?? '',
        // 旧的参数
        previousRoute?.settings.arguments ?? {},
      ));
    } catch (e) {
      Log.e('AppRoutesObserver] didPop: $e');
    }
  }

  @override
  void didRemove(Route route, Route? previousRoute) {
    Log.d('[AppRoutesObserver] didRemove: ${route.settings.name}');
    super.didRemove(route, previousRoute);
    _appRoutes.remove(route);
    try {
      afterBackRouteStreamController.add(MapEntry(
        previousRoute?.settings.name ?? '',
        // 旧的参数
        previousRoute?.settings.arguments ?? {},
      ));
    } catch (e) {
      Log.e('AppRoutesObserver] didRemove: $e');
    }
  }

  @override
  void didReplace({Route? newRoute, Route? oldRoute}) {
    Log.d(
        '[AppRoutesObserver] didReplace: old=${oldRoute?.settings.name}, new=${newRoute?.settings.name}');
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);

    // 处理 Get.offAllNamed 的情况
    // 当新路由不为空且旧路由为空时，说明是清空所有路由后添加新路由
    if (newRoute != null && oldRoute == null) {
      Log.d('[AppRoutesObserver] 检测到路由栈清空操作，清空内部路由列表');
      _appRoutes.clear();
      _appRoutes.insert(0, newRoute);
      return;
    }

    // 处理正常的路由替换
    if (oldRoute != null) {
      _appRoutes.remove(oldRoute);
    }
    if (newRoute != null) {
      // 如果新路由不在列表中，则添加
      if (!_appRoutes.contains(newRoute)) {
        _appRoutes.insert(0, newRoute);
      }
    }
  }

  /// 获取当前路由列表的副本
  List<Route> get currentRoutes => List.from(_appRoutes);

  /// 移除指定路由页面，调用前需要判断当前路由是否是目标路由，
  /// Get.currentRoute == RouterNames.callingP2PRoomPage
  /// 如果是当前路由，请直接使用Get.back()
  Future removeRoute<S extends GetxController>(String routeName) async {
    if (Get.currentRoute == routeName) {
      Get.back();
      return;
    }

    for (Route route in _appRoutes) {
      if (route.settings.name == null) {
        continue;
      }
      Uri? url = Uri.tryParse(route.settings.name!);
      if (url != null && url.path == routeName) {
        _appRoutes.remove(route);
        // 从路由栈中移除
        Get.removeRoute(route);
        // 移除controller
        await Get.delete<S>(force: true);
        break;
      }
    }
  }

  /// 移除指定路由页面直到指定路由
  /// 如果不包含指定路由，则不进行任何操作
  Future removeUntilRoute(String routeName) async {
    // 当前路由可能不是正在可见的页面，如：bottomsheet，如果bottomsheet设置了路由名称，会添加到路由栈中
    // if (Get.currentRoute == routeName) {
    //   return;
    // }
    if (!containsRoute(routeName)) {
      return;
    }

    while (_appRoutes.isNotEmpty) {
      Route route = _appRoutes.removeAt(0);
      if (route.settings.name == null) {
        // 重新加回去
        _appRoutes.add(route);
        break;
      }
      Uri? url = Uri.tryParse(route.settings.name!);
      if (url != null && url.path == routeName) {
        // 重新加回去
        _appRoutes.add(route);
        break;
      }
      // 从路由栈中移除，调用back来删除
      Get.back();
    }
  }
}
