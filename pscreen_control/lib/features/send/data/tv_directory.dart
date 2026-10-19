import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// 预设电视设备。
class TvDevice {
  const TvDevice({required this.name, required this.account});

  final String name;
  final String account;
}

/// 预设电视列表：assets/tvs.json + 名称查询。
class TvDirectory {
  TvDirectory({this.devices = const <TvDevice>[]});

  List<TvDevice> devices; // 可变字段（loadFromAssets 赋值）

  static List<TvDevice> parseJson(String raw) {
    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is! List) return const <TvDevice>[];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map((m) => TvDevice(
                name: (m['name'] as String?) ?? '',
                account: (m['account'] as String?) ?? '',
              ))
          .where((d) => d.account.isNotEmpty)
          .toList();
    } catch (_) {
      return const <TvDevice>[];
    }
  }

  /// 从 assets 加载（main/DI 注册后调用一次）。
  Future<void> loadFromAssets() async {
    final String raw = await rootBundle.loadString('assets/tvs.json');
    devices = parseJson(raw);
  }

  /// 账号 → 显示名；未命中返回账号。
  String nameOf(String account) {
    for (final TvDevice d in devices) {
      if (d.account == account) return d.name;
    }
    return account;
  }
}
