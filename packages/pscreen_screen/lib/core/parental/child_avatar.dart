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

/// 头像选择条目：圆形图 + 选中描边 + 右下角 ✓ + 右上角 X（可选删除）。
///
/// 家庭档案编辑器与设备级档案编辑器共用，避免两套头像 UI 各写一份。
class AvatarTile extends StatelessWidget {
  const AvatarTile({
    required this.size,
    required this.selected,
    required this.onTap,
    required this.child,
    this.deleteAction,
  });

  final double size;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  /// 非空时右上角显示 X 按钮；预设头像不传入这个。
  final VoidCallback? deleteAction;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? theme.colorScheme.primary : Colors.transparent,
            width: selected ? 3 : 0,
          ),
        ),
        child: Stack(
          children: <Widget>[
            Padding(
              padding: EdgeInsets.all(selected ? 1 : 0),
              child: child,
            ),
            if (selected)
              Positioned(
                right: 2,
                bottom: 2,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.check,
                    size: 14,
                    color: theme.colorScheme.onPrimary,
                  ),
                ),
              ),
            if (deleteAction != null)
              Positioned(
                top: -2,
                right: -2,
                child: GestureDetector(
                  onTap: deleteAction,
                  // 独立点击区：不触发外层 onTap。
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    child: const Icon(
                      Icons.close,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
