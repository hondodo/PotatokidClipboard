import 'package:flutter/material.dart';
import 'package:potatokid_screen/app/app_flavor.dart';
import 'package:potatokid_screen/features/app/application/touch_back_controller.dart';

/// 触屏「返回」按钮（`phone` / `board` 显示，`tv` 不显示）。
///
/// 为什么需要：遥控端的返回键是实体键，触屏没有等价物。若非直播页（时间 / 设置）
/// 没有可见的返回入口，触屏用户一旦进去就出不来——这正是本按钮要补的缺口。
///
/// 行为：点击复用 [TouchBackController]，与遥控返回键走**同一条**分层逻辑
/// （行内编辑 → 正文焦点 → 回直播页），不新增第二套返回规则。
///
/// flavor 口径：
/// - `phone`（手机 / 平板）：显示；
/// - `board`（电视桌面，触屏）：显示；
/// - `tv`（电视 / 盒子）：**不显示**——这类设备只有遥控，返回键由实体键承担，
///   多一个可点按钮反而与遥控焦点树打架。
class TouchBackButton extends StatelessWidget {
  const TouchBackButton({super.key});

  @override
  Widget build(BuildContext context) {
    // tv 是唯一没有触屏的变体：它的返回由实体遥控键承担。
    if (AppFlavorConfig.flavor == AppFlavor.tv) {
      return const SizedBox.shrink();
    }
    return Material(
      color: const Color(0xCC161D2C),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => TouchBackController.instance.requestBack(context),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.arrow_back_rounded, color: Colors.white, size: 22),
              SizedBox(width: 6),
              Text(
                '返回',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
