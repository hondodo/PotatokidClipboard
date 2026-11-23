import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'package:pscreen_home/app/config/ha_config.dart';

/// 卡片图标（网络图片 + 磁盘缓存）。
///
/// - `http(s)://` 绝对路径直接使用；
/// - `/api/files/...` 相对路径按 [HaConfig.serverBaseUrl] 拼接，
///   因此服务端只保存相对路径，yuntu IP 变化不会让历史图标失效；
/// - 下载后按 URL 缓存到应用文档目录的 `card_icon_cache`，
///   内存里再缓存一次 ImageProvider，避免每张卡片重建都读盘/请求。
class CachedCardIcon extends StatefulWidget {
  const CachedCardIcon({
    super.key,
    required this.icon,
    required this.size,
    required this.fallback,
  });

  final String icon;
  final double size;
  final Widget Function() fallback;

  static final Map<String, ImageProvider> _memory = <String, ImageProvider>{};

  /// 只在这里判断「是不是图片」；符号 / Material 名返回 null。
  static String? resolveUrl(String raw) {
    final String value = raw.trim();
    if (value.isEmpty) return null;
    if (value.startsWith('http://') || value.startsWith('https://')) return value;
    if (value.startsWith('/')) {
      final String base = HaConfig.serverBaseUrl.trim();
      if (base.isEmpty) return null;
      return '$base$value';
    }
    return null;
  }

  @override
  State<CachedCardIcon> createState() => _CachedCardIconState();
}

class _CachedCardIconState extends State<CachedCardIcon> {
  ImageProvider? _provider;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant CachedCardIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.icon != widget.icon) {
      _provider = null;
      _load();
    }
  }

  void _setProvider(ImageProvider provider) {
    if (mounted) setState(() => _provider = provider);
  }

  Future<void> _load() async {
    final String? url = CachedCardIcon.resolveUrl(widget.icon);
    if (url == null) return;
    final ImageProvider? cached = CachedCardIcon._memory[url];
    if (cached != null) {
      _setProvider(cached);
      return;
    }

    try {
      final Directory documents = await getApplicationDocumentsDirectory();
      final String cacheDir = '${documents.path}${Platform.pathSeparator}card_icon_cache';
      // base64url 文件名与 URL 一一对应，且不含路径分隔符。
      final String name = base64Url.encode(utf8.encode(url)).replaceAll('=', '');
      final File file = File('$cacheDir${Platform.pathSeparator}$name');
      if (await file.exists()) {
        final FileImage provider = FileImage(file);
        CachedCardIcon._memory[url] = provider;
        _setProvider(provider);
        return;
      }

      final http.Response response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) return;
      await Directory(cacheDir).create(recursive: true);
      final File temporary = File('${file.path}.part');
      await temporary.writeAsBytes(response.bodyBytes, flush: true);
      try {
        await temporary.rename(file.path);
      } on FileSystemException {
        // 另一个卡片可能已经写入同名缓存，直接用它即可。
      }
      final FileImage provider = FileImage(file);
      CachedCardIcon._memory[url] = provider;
      _setProvider(provider);
    } catch (_) {
      // path_provider / http 在无插件环境不可用时，退回 Flutter 自带网络缓存。
      try {
        final NetworkImage provider = NetworkImage(url);
        CachedCardIcon._memory[url] = provider;
        _setProvider(provider);
      } catch (_) {
        // 保持 fallback。
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ImageProvider? provider = _provider;
    if (provider == null) return widget.fallback();
    return Image(
      image: provider,
      width: widget.size,
      height: widget.size,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => widget.fallback(),
    );
  }
}
