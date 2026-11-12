import 'package:flutter/material.dart';
import 'package:pscreen_home/core/device/device_display_name.dart';
import 'package:pscreen_home/features/parental/data/parental_admin_api.dart';
import 'package:pscreen_home/features/parental/domain/parental_config.dart';
import 'package:pscreen_screen/core/network/realtime_channel.dart';

/// 家长端跨页面复用的工具与回调集合，避免把大段渲染塞进 `ParentalPage`。

/// 设备显示名（家长端统一口径）。
String parentalTvName(ParentalMachine machine) => DeviceDisplayName.resolve(
      account: machine.commAccount.isEmpty ? machine.id : machine.commAccount,
      alias: machine.alias,
      displayName: machine.commDisplayName,
      machineName: machine.nameSet ? machine.name : '',
    );

/// 解锁方式标签。
const Map<String, String> kUnlockModeLabels = <String, String>{
  'remote': '远程确认（手机弹层）',
  'pin': 'PIN 兜底',
  'arith': '算术题兜底',
  'quiz': '答题解锁（使用儿童题库）',
};

String unlockModeLabel(String mode) => kUnlockModeLabels[mode] ?? mode;

/// 家长端各 Tab / 子页需要的副作用回调（数据加载、保存、解锁、导航等）。
///
/// 由 `ParentalPage`（持有全部状态）在 build 时构造并下发给外部 widget，
/// 使页面组件保持纯渲染 + 导航，不反向耦合状态类。
class ParentalActions {
  const ParentalActions({
    required this.reload,
    required this.saveConfig,
    required this.unlock,
    required this.openDeviceManager,
    required this.push,
    required this.sendRemoteCommand,
    required this.refreshPermission,
    required this.toggleChildLock,
    required this.addChildExtra,
    required this.editChild,
    required this.unbind,
    required this.selectDevice,
    required this.renameMachine,
  });

  /// 重新拉取设备 / 配置 / 事件。
  final Future<void> Function() reload;

  /// 保存整份 parental 配置（乐观更新 + 服务端回读）。
  final Future<void> Function(ParentalConfig next) saveConfig;

  /// 下发解锁命令（补发 `parental_unlock`）。
  final Future<void> Function(RealtimeEvent event) unlock;

  /// 打开电视绑定管理底部弹层。
  final Future<void> Function() openDeviceManager;

  /// 下钻到某个全屏子页，返回后自动补拉事件。
  final Future<void> Function(Widget page) push;

  /// 向被控设备发送遥控命令。
  final Future<void> Function(String command) sendRemoteCommand;

  /// 重新登录并刷新角色（空态权限自愈）。
  final Future<void> Function() refreshPermission;

  /// 暂停 / 解锁某个孩子（保存配置 + 提示）。
  final void Function(ParentalChild child) toggleChildLock;

  /// 给某个孩子加时 15 分钟（保存配置 + 提示）。
  final void Function(ParentalChild child) addChildExtra;

  /// 打开某个孩子的档案编辑页（选人页），保存后写回。
  final void Function(ParentalChild child) editChild;

  /// 解绑某台电视（仅家长）。
  final void Function(String deviceId) unbind;

  /// 切换「当前配置目标」电视（去掉顶部下拉后，由「我的」页按设备选择）。
  final void Function(ParentalMachine machine) selectDevice;

  /// 重命名某台电视（仅自己可见的别名）。
  final void Function(ParentalMachine machine) renameMachine;
}
