import 'package:flutter/material.dart';
import 'package:pscreen_home/features/home/presentation/components/ha_domain_icons.dart';

/// 设备类型图标徽章：圆角方块底 + 类型色图标。
///
/// 统一首页所有卡片左上角的设备图标，按 domain 自动配色，关闭态保留类型色
/// （仅降透明度），让老人「扫一眼颜色 + 图标」即可认出设备类型，而非逐张读字。
///
/// [domain] 与 [color] 至少提供一个：传 [domain] 时图标与配色自动取自
/// [HaDomainColors] / [HaDomainIcons]；传 [color] 可显式覆盖（如灯卡固定暖黄）。
class DeviceTypeIcon extends StatelessWidget {
  const DeviceTypeIcon({
    super.key,
    this.domain,
    this.color,
    this.icon,
    required this.on,
    this.isToggling = false,
    this.size = 54,
  }) : assert(domain != null || color != null, 'domain 与 color 至少提供一个');

  final String? domain;

  /// 显式配色；非空时覆盖按 domain 取到的类型色。
  final Color? color;

  /// 显式图标；为空时按 domain 取 [HaDomainIcons.of]。
  final IconData? icon;

  /// 设备是否开启（影响配色饱和度）
  final bool on;

  /// 指令执行中（显示转圈而非图标）
  final bool isToggling;

  /// 徽章边长（默认 54，墙面屏老人友好）
  final double size;

  Color get _color => color ?? HaDomainColors.of(domain ?? '');

  IconData get _icon => icon ?? HaDomainIcons.of(domain ?? '');

  @override
  Widget build(BuildContext context) {
    final Color base = _color;
    final Color tint = base.withValues(alpha: on ? 0.18 : 0.08);
    final Color fg = on ? base : base.withValues(alpha: 0.6);
    final double radius = size * 0.3;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: isToggling
          ? Center(
              child: SizedBox(
                width: size * 0.36,
                height: size * 0.36,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: fg,
                ),
              ),
            )
          : Icon(
              _icon,
              size: size * 0.52,
              color: fg,
            ),
    );
  }
}
