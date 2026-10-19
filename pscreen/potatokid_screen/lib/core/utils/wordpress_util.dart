import 'package:dio/dio.dart';

import 'app_settings.dart';

/// WordPress 密码保护文章抓取失败（密码错误或未提供）。
class WordPressPassException implements Exception {
  WordPressPassException(this.message);

  final String message;

  @override
  String toString() => 'WordPressPassException: $message';
}

/// WordPress 文章内容抓取工具。
class WordPressUtil {
  static const String _passFormMarker = 'post-password-form';
  static const String _entryContentMarker = 'entry-content';
  static const String _postFlairMarker = 'jp-post-flair';
  static const String _sharedaddyMarker = 'sharedaddy';

  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      followRedirects: true,
      maxRedirects: 5,
      headers: <String, String>{
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      },
    ),
  );

  /// 抓取文章正文纯文本。
  ///
  /// [password] 缺省时读取 [AppSettings.instance.wpPassword]。
  /// 文章未设密码时直接返回内容；设密码且校验通过时返回解密正文。
  /// 密码错误或未提供时抛 [WordPressPassException]。
  static Future<String> fetchPostContent(
    String url, {
    String? password,
  }) async {
    final String effectivePassword = password ?? AppSettings.instance.wpPassword;

    // 第 1 步：GET 文章页，检测是否被密码保护。
    Response<String> response = await _dio.get<String>(url);
    final String html = response.data ?? '';

    if (!html.contains(_passFormMarker)) {
      return _extractContent(html);
    }

    // 第 2 步：POST wp-login.php?action=postpass 校验密码。
    if (effectivePassword.isEmpty) {
      throw WordPressPassException('文章受密码保护，但未提供密码');
    }

    final Uri uri = Uri.parse(url);
    final String origin = '${uri.scheme}://${uri.host}';

    // POST 不自动跟随重定向：错误/正确密码均返回 302 + wp-postpass cookie，
    // 需要显式捕获 cookie 供第 3 步使用。
    Response<String> postResponse;
    try {
      postResponse = await _dio.post<String>(
        '$origin/wp-login.php?action=postpass',
        data: <String, String>{
          'post_password': effectivePassword,
          'Submit': '确定',
        },
        options: Options(
          headers: <String, String>{
            'Content-Type': 'application/x-www-form-urlencoded',
            'Referer': url,
          },
          followRedirects: false,
          validateStatus: (int? status) => status != null && status < 400,
        ),
      );
    } on DioException {
      throw WordPressPassException('密码校验请求失败，请检查网络');
    }

    final String? passCookie =
        _extractPostPassCookie(postResponse.headers.map['set-cookie']);

    // 第 3 步：带 wp-postpass cookie 重新 GET 文章页，验证密码是否正确。
    response = await _dio.get<String>(
      url,
      options: passCookie != null
          ? Options(headers: <String, String>{'Cookie': passCookie})
          : null,
    );
    final String htmlAfter = response.data ?? '';

    if (htmlAfter.contains(_passFormMarker)) {
      throw WordPressPassException('WordPress 密码校验未通过');
    }

    return _extractContent(htmlAfter);
  }

  /// 从 `Set-Cookie` 响应头中提取 `wp-postpass_*` cookie（名称=值部分）。
  static String? _extractPostPassCookie(List<String>? setCookies) {
    if (setCookies == null) {
      return null;
    }
    for (final String header in setCookies) {
      final String firstPair = header.split(';').first.trim();
      if (firstPair.startsWith('wp-postpass_')) {
        return firstPair;
      }
    }
    return null;
  }

  /// 从 HTML 中抽取 `<div class="entry-content">` 内的可见文本。
  ///
  /// 尾部的 Jetpack 分享/点赞组件（jp-post-flair / sharedaddy）会先被截除。
  static String _extractContent(String html) {
    final int start = html.indexOf(_entryContentMarker);
    if (start == -1) {
      return '';
    }

    int contentStart = html.indexOf('>', start);
    if (contentStart == -1) {
      return '';
    }
    contentStart += 1;

    int contentEnd = html.indexOf(_postFlairMarker, contentStart);
    if (contentEnd == -1) {
      contentEnd = html.indexOf(_sharedaddyMarker, contentStart);
    }
    if (contentEnd == -1) {
      contentEnd = html.indexOf('</div>', contentStart);
    }
    if (contentEnd == -1) {
      contentEnd = html.length;
    }

    final String raw = html.substring(contentStart, contentEnd);
    final String text = _htmlToText(raw);
    return text.trim();
  }

  /// HTML → 可见文本：去 script/style，块级标签转行，去标签，实体解码。
  static String _htmlToText(String html) {
    String text = html.replaceAll(RegExp(r'<script[^>]*>[\s\S]*?</script>', caseSensitive: false), '');
    text = text.replaceAll(RegExp(r'<style[^>]*>[\s\S]*?</style>', caseSensitive: false), '');
    text = text.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
    text = text.replaceAll(RegExp(r'</(p|div|h[1-6]|li|tr)>', caseSensitive: false), '\n');
    text = text.replaceAll(RegExp(r'<[^>]+>'), '');
    return _decodeEntities(text);
  }

  /// HTML 实体解码（常见命名实体 + 数字实体）。
  static String _decodeEntities(String text) {
    String result = text;
    const Map<String, String> named = <String, String>{
      '&amp;': '&',
      '&lt;': '<',
      '&gt;': '>',
      '&quot;': '"',
      '&#39;': "'",
      '&apos;': "'",
      '&nbsp;': ' ',
    };
    named.forEach((String key, String value) {
      result = result.replaceAll(key, value);
    });
    result = result.replaceAllMapped(
      RegExp(r'&#x([0-9a-fA-F]+);'),
      (Match m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)),
    );
    result = result.replaceAllMapped(
      RegExp(r'&#(\d+);'),
      (Match m) => String.fromCharCode(int.parse(m.group(1)!)),
    );
    return result;
  }
}
