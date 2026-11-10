import 'package:flutter/material.dart';

/// 内置儿童头像常量（`preset:` 前缀后直接拼这里的值）。
/// 新增头像只需把 PNG 丢进 `assets/parental/avatars/`，然后在这里加一行。
/// 键与文件名一一对应：`avatar001` → `avatar001.png`。
const List<String> kPresetAvatarKeys = <String>[
  'avatar001',
  'avatar002',
  'avatar003',
];

/// 给定 `ChildProfile.avatar` 值（可为 null），解析为可显示的头像 Widget。
///
/// - `preset:xxx` → 内置 `Image.asset('packages/pscreen_screen/assets/parental/avatars/xxx.png')`
/// - `http(s)://...` → `Image.network(...)`
/// - 空 / 非法 → `fallback`（通常是带名字首字的 CircleAvatar）
class ChildAvatarWidget extends StatelessWidget {
  const ChildAvatarWidget({
    super.key,
    required this.avatar,
    required this.fallback,
    this.width,
    this.height,
    this.clipBehavior = Clip.antiAlias,
  });

  final String? avatar;
  final Widget fallback;
  final double? width;
  final double? height;
  final Clip clipBehavior;

  String? get _presetResource {
    final String? raw = avatar;
    if (raw == null || raw.isEmpty) return null;
    if (!raw.startsWith('preset:')) return null;
    final String key = raw.substring('preset:'.length);
    if (kPresetAvatarKeys.contains(key)) {
      return 'packages/pscreen_screen/assets/parental/avatars/$key.png';
    }
    return null;
  }

  String? get _networkUrl {
    final String? raw = avatar;
    if (raw == null || raw.isEmpty) return null;
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final String? preset = _presetResource;
    if (preset != null) {
      return Image.asset(
        preset,
        width: width,
        height: height,
        fit: BoxFit.cover,
      );
    }
    final String? url = _networkUrl;
    if (url != null) {
      return Image.network(
        url,
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      );
    }
    return fallback;
  }
}
