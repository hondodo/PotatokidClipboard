/// 把「网页查看地址」还原成「原始文件地址」的通用解析器。
///
/// 代码托管平台（GitHub / Gitee / GitLab…）的**文件页地址返回的是 HTML 查看页**，
/// 直接请求拿不到文件正文。要取正文必须改写成该平台的 raw 直链。
///
/// 每个平台一条改写规则，统一注册在 [_rules]；以后要支持新平台，
/// 只要写一个同签名的函数并追加进去即可，调用方无需改动。
class RawContentUrlResolver {
  const RawContentUrlResolver._();

  /// 规则签名：适用并成功改写时返回新地址，不适用时返回 null。
  ///
  /// 按注册顺序尝试，第一个返回非 null 的生效。
  static final List<String? Function(Uri uri)> _rules = <String? Function(Uri uri)>[
    _githubViewToRaw,
    // 需要支持更多平台时在这里追加，例如：
    // _giteeViewToRaw,
    // _gitlabViewToRaw,
  ];

  /// 把 [url] 解析成能直接取到正文的地址；无需改写时原样返回。
  static String resolve(String url) {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null) return url;
    for (final String? Function(Uri uri) rule in _rules) {
      final String? rewritten = rule(uri);
      if (rewritten != null) return rewritten;
    }
    return url;
  }

  /// GitHub：`/{owner}/{repo}/(blob|raw)/{ref}/{path}` → raw.githubusercontent.com。
  ///
  /// 例：`https://github.com/o/r/blob/main/a/b.txt`
  /// 　→ `https://raw.githubusercontent.com/o/r/main/a/b.txt`
  ///
  /// 两个实现细节：
  /// - 用**已编码的 [Uri.path] 做字符串拼接**（不用 `pathSegments`），
  ///   避免中文/空格等路径被解码后再编码导致地址不一致；
  /// - `{ref}` 只取一段（`main` / `master` / tag）。分支名自带 `/` 时无法离线还原，
  ///   这类分支请直接写 raw 地址，或用 GitHub 的 `?raw=true` 跳转。
  ///
  /// 其余地址（如 `releases/download/...` 下载直链）不是查看页，原样返回。
  static String? _githubViewToRaw(Uri uri) {
    final String host = uri.host.toLowerCase();
    if (host != 'github.com' && !host.endsWith('.github.com')) return null;
    final RegExpMatch? match = RegExp(
      r'^/([^/]+)/([^/]+)/(?:blob|raw)/([^/]+)/(.+)$',
    ).firstMatch(uri.path);
    if (match == null) return null;
    final String query = uri.hasQuery ? '?${uri.query}' : '';
    return 'https://raw.githubusercontent.com/${match.group(1)}/${match.group(2)}/'
        '${match.group(3)}/${match.group(4)}$query';
  }
}