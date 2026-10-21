/// 需要统一成「`前缀-` + 其余」的频道名前缀白名单（大小写不敏感）。
///
/// 数据源里同一个台常见两种写法（`CCTV1` / `CCTV-1`），需要新增前缀
/// （如 `HBO`、`BBC`）时在这里加一项即可。
const List<String> _normalizePrefixes = <String>['CCTV', 'CETV'];

final RegExp _leadingSpaces = RegExp(r'^\s+');

/// 归一化频道名：`CCTV1` → `CCTV-1`、`cctv5+` → `CCTV-5+`、`CCTV4K` → `CCTV-4K`。
///
/// 为什么需要：m3u/接口里 `CCTV1` 与 `CCTV-1` 混用，不统一会导致
/// 1. 同一个台在列表里出现两次（各自只带一部分源，而不是合成一个台）；
/// 2. `tv_name_order.txt` / `tv_name_hide.txt` 里写的 `CCTV-1` 匹配不上接口给的 `CCTV1`。
///
/// 规则（**只动名字开头的白名单前缀**，其余部分一律原样保留）：
/// - 前缀大小写不敏感，输出统一为大写；
/// - 前缀后面紧跟的不是 `-` 时补一个 `-`，前缀与其余部分之间的空白同时去掉
///   （`CCTV 1` 也会变成 `CCTV-1`）；
/// - 已经带 `-` 的名字原样返回，因此本函数**幂等**，可反复调用；
/// - 带后缀的版本不会被并到一起：`CCTV-4 欧洲`、`CCTV4K真4K` 各自保持独立。
String normalizeChannelName(String raw) {
  final String name = raw.trim();
  for (final String prefix in _normalizePrefixes) {
    // 名字本身不比前缀长（如就叫 `CCTV`）时不动。
    if (name.length <= prefix.length) continue;
    if (name.substring(0, prefix.length).toUpperCase() != prefix) continue;
    final String rest = name.substring(prefix.length).replaceFirst(_leadingSpaces, '');
    return rest.startsWith('-') ? '$prefix$rest' : '$prefix-$rest';
  }
  return name;
}
