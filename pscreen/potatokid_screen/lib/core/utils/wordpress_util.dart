import 'package:dio/dio.dart';

import 'app_settings.dart';

/// WordPress 密码保护文章访问失败（密码未设置、校验失败或正文为空）。
class WordPressPassException implements Exception {
  const WordPressPassException(this.message);

  final String message;

  @override
  String toString() => 'WordPressPassException: $message';
}

/// WordPress 文章内容抓取工具。
///
/// 流程：GET 文章页检测 `post-password-form` → 若受保护则
/// POST `wp-login.php?action=postpass`（302 + `wp-postpass_*` cookie）
/// → 带 cookie 重新 GET 验证密码 → 抽取 `entry-content` 正文纯文本。
class WordPressUtil {
  WordPressUtil._();

  static const String _passFormMarker = 'post-password-form';

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
  /// 密码未设置、校验失败或正文为空 → [WordPressPassException]；
  /// 网络错误 → [DioException]（与 GET 步骤一致透传）。
  static Future<String> fetchPostContent(
    String url, {
    String? password,
  }) async {
    if (password == null) {
      await AppSettings.instance.ensureLoaded();
    }
    final String effectivePassword = password ?? AppSettings.instance.wpPassword;

    // 第 1 步：GET 文章页，检测是否被密码保护。
    Response<String> response = await _dio.get<String>(url);
    final String html = response.data ?? '';

    if (!html.contains(_passFormMarker)) {
      final String content = _extractEntryContent(html);
      if (content.isEmpty) {
        throw const WordPressPassException('正文为空');
      }
      return content;
    }

    // 第 2 步：POST wp-login.php?action=postpass 校验密码。
    if (effectivePassword.isEmpty) {
      throw const WordPressPassException('文章受密码保护，但未提供密码');
    }

    final Uri uri = Uri.parse(url);
    final String origin = '${uri.scheme}://${uri.host}';

    // POST 不自动跟随重定向：错误/正确密码均返回 302 + wp-postpass cookie，
    // 需要显式捕获 cookie 供第 3 步使用。网络错误透传 [DioException]。
    final Response<String> postResponse = await _dio.post<String>(
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
      throw const WordPressPassException('WordPress 密码校验未通过');
    }

    final String content = _extractEntryContent(htmlAfter);
    if (content.isEmpty) {
      throw const WordPressPassException('正文为空');
    }
    return content;
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

  /// 解析 `entry-content` div 为纯文本。
  ///
  /// 定位 `<body>` 后首个 `class="entry-content`；div 范围用
  /// `<div>`/`</div>` 深度配对求出，并截去正文之后的 Jetpack 附加组件
  /// （`jp-post-flair`/`sharedaddy`）；再去标签、解码常见实体。
  static String _extractEntryContent(String html) {
    final int bodyIdx = html.indexOf('<body');
    final int clsIdx = html.indexOf(
      'class="entry-content',
      bodyIdx < 0 ? 0 : bodyIdx,
    );
    if (clsIdx < 0) return '';
    final int openEnd = html.indexOf('>', clsIdx);
    if (openEnd < 0) return '';

    int end = _divContentEnd(html, openEnd);
    final int cap = _indexOfAny(html, const <String>[
      '<div id="jp-post-flair"',
      '<div class="sharedaddy',
    ], openEnd);
    if (cap >= 0 && cap < end) end = cap;

    final String raw = html.substring(openEnd + 1, end);
    return _htmlToText(raw);
  }

  /// 从 [fromIdx]（开标签 `>` 之后）起，深度配对求 entry-content div 的结束下标。
  static int _divContentEnd(String html, int fromIdx) {
    final List<int> opens = RegExp(r'<div[\s>]')
        .allMatches(html)
        .map((Match m) => m.start)
        .toList(growable: false);
    final List<int> closes = RegExp(r'</div>')
        .allMatches(html)
        .map((Match m) => m.start)
        .toList(growable: false);

    int oi = 0;
    int ci = 0;
    while (oi < opens.length && opens[oi] <= fromIdx) {
      oi++;
    }
    while (ci < closes.length && closes[ci] <= fromIdx) {
      ci++;
    }

    int depth = 1;
    while (ci < closes.length) {
      final int nextOpen = oi < opens.length ? opens[oi] : -1;
      final int nextClose = closes[ci];
      if (nextOpen >= 0 && nextOpen < nextClose) {
        depth++;
        oi++;
      } else {
        depth--;
        ci++;
        if (depth == 0) return nextClose;
      }
    }
    return html.length;
  }

  /// 返回 [markers] 中任一字符串在 [html] 内（下标 ≥ [fromIdx]）的最早下标；全无则 -1。
  static int _indexOfAny(String html, List<String> markers, int fromIdx) {
    int best = -1;
    for (final String marker in markers) {
      final int idx = html.indexOf(marker, fromIdx);
      if (idx >= 0 && (best < 0 || idx < best)) best = idx;
    }
    return best;
  }

  /// 去 script/style 与标签、块级换行、解码常见实体、压缩空行。
  static String _htmlToText(String raw) {
    String text = raw
        .replaceAll(
          RegExp(r'<script[^>]*>[\s\S]*?</script>', caseSensitive: false),
          '',
        )
        .replaceAll(
          RegExp(r'<style[^>]*>[\s\S]*?</style>', caseSensitive: false),
          '',
        )
        .replaceAll(
          RegExp(
            r'</(?:p|div|h[1-6]|li|blockquote|pre|figcaption|figure)>',
            caseSensitive: false,
          ),
          '\n',
        )
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#8217;', "'")
        .replaceAll('&rsquo;', "'")
        .replaceAll('&#8220;', '"')
        .replaceAll('&#8221;', '"')
        .replaceAll('&ldquo;', '"')
        .replaceAll('&rdquo;', '"');
    // 通用十进制数字实体（如 &#8230;），带范围防护。
    text = text.replaceAllMapped(
      RegExp(r'&#(\d+);'),
      (Match m) {
        final int? code = int.tryParse(m.group(1)!);
        return (code != null && code > 0 && code <= 0x10FFFF)
            ? String.fromCharCode(code)
            : '';
      },
    );
    // 十六进制数字实体（如 &#x2026;），带同样的范围防护。
    text = text.replaceAllMapped(
      RegExp(r'&#x([0-9a-fA-F]+);'),
      (Match m) {
        final int? code = int.tryParse(m.group(1)!, radix: 16);
        return (code != null && code > 0 && code <= 0x10FFFF)
            ? String.fromCharCode(code)
            : '';
      },
    );
    // &amp; 最后解码，避免 &amp;lt; 被双重解码。
    text = text.replaceAll('&amp;', '&');
    return text.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }
}
