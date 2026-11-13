import 'package:flutter/material.dart';
import 'package:pscreen_home/core/device/device_display_name.dart';
import 'package:pscreen_home/features/parental/data/parental_admin_api.dart';
import 'package:pscreen_home/features/parental/domain/parental_config.dart';
import 'package:pscreen_home/features/parental/domain/parental_share.dart';
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

/// D-01 冲突处理三选一结果。
enum ParentalConflictChoice { viewDiff, overwrite, discard }

/// 并发写入冲突对话框：查看差异 / 以我的版本覆盖 / 放弃。
///
/// - [mine] / [theirs] 用于「查看差异」，只比对业务字段（忽略版本与写入者）；
/// - 返回 [ParentalConflictChoice.discard] 表示调用方应回读服务端最新值；
/// - 「覆盖」由调用方携带服务端最新版本号重新提交。
Future<ParentalConflictChoice> showParentalConflictDialog(
  BuildContext context, {
  required String title,
  required String message,
  Map<String, dynamic>? mine,
  Map<String, dynamic>? theirs,
}) async {
  while (true) {
    final ParentalConflictChoice? choice =
        await showDialog<ParentalConflictChoice>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(ParentalConflictChoice.discard),
            child: const Text('放弃'),
          ),
          if (mine != null && theirs != null)
            TextButton(
              onPressed: () => Navigator.of(context).pop(ParentalConflictChoice.viewDiff),
              child: const Text('查看差异'),
            ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(ParentalConflictChoice.overwrite),
            child: const Text('以我的版本覆盖'),
          ),
        ],
      ),
    );
    if (choice != ParentalConflictChoice.viewDiff) {
      return choice ?? ParentalConflictChoice.discard;
    }
    if (!context.mounted) return ParentalConflictChoice.discard;
    if (mine == null || theirs == null) return ParentalConflictChoice.discard;
    // showDialog 的 builder 闭包内不会再做空提升，提前取出非空引用。
    final Map<String, dynamic> mineMap = mine;
    final Map<String, dynamic> theirsMap = theirs;
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('差异对比'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Table(
              columnWidths: const <int, TableColumnWidth>{
                0: FlexColumnWidth(1.1),
                1: FlexColumnWidth(1),
                2: FlexColumnWidth(1),
              },
              border: TableBorder.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
              children: <TableRow>[
                const TableRow(
                  children: <Widget>[
                    Padding(padding: EdgeInsets.all(6), child: Text('字段')),
                    Padding(padding: EdgeInsets.all(6), child: Text('我的版本')),
                    Padding(padding: EdgeInsets.all(6), child: Text('服务端')),
                  ],
                ),
                ..._diffRows(mineMap, theirsMap).map(
                  (List<String> row) => TableRow(
                    children: row
                        .map(
                          (String cell) => Padding(
                            padding: const EdgeInsets.all(6),
                            child: Text(cell, style: const TextStyle(fontSize: 12)),
                          ),
                        )
                        .toList(growable: false),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: <Widget>[
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('返回'),
          ),
        ],
      ),
    );
    if (!context.mounted) return ParentalConflictChoice.discard;
  }
}

/// 只列出业务字段差异；版本 / 写入者 / 时间戳属元数据，不参与对比。
List<List<String>> _diffRows(
  Map<String, dynamic> mine,
  Map<String, dynamic> theirs,
) {
  const Set<String> ignored = <String>{
    'revision',
    'baseRevision',
    'updatedBy',
    'updatedAt',
  };
  final Set<String> keys = <String>{
    ...mine.keys.where((String k) => !ignored.contains(k)),
    ...theirs.keys.where((String k) => !ignored.contains(k)),
  };
  final List<List<String>> rows = <List<String>>[];
  for (final String key in keys) {
    final String a = '${mine[key] ?? '（无）'}';
    final String b = '${theirs[key] ?? '（无）'}';
    if (a == b) continue;
    rows.add(<String>[key, a, b]);
  }
  if (rows.isEmpty) rows.add(const <String>['（无业务字段差异）', '', '']);
  return rows;
}

/// 家长端各 Tab / 子页需要的副作用回调（数据加载、保存、解锁、导航等）。
///
/// 由 `ParentalPage`（持有全部状态）在 build 时构造并下发给外部 widget，
/// 使页面组件保持纯渲染 + 导航，不反向耦合状态类。
class ParentalActions {
  const ParentalActions({
    required this.reload,
    required this.saveConfig,
    required this.saveDeviceSettings,
    required this.unlock,
    required this.openDeviceManager,
    required this.openLoginExisting,
    required this.openCreateAccount,
    required this.hasClaimedAccount,
    required this.push,
    required this.sendRemoteCommand,
    required this.refreshPermission,
    required this.toggleChildLock,
    required this.addChildExtra,
    required this.editChild,
    required this.unbind,
    required this.selectDevice,
    required this.renameMachine,
    required this.openShareManagement,
    required this.loadShareView,
    required this.setSharedTo,
    required this.addSharedRef,
    required this.cancelSharedRef,
  });

  /// 重新拉取设备 / 配置 / 事件。
  final Future<void> Function() reload;

  /// 保存整份 parental 配置（乐观更新 + 服务端回读）。
  final Future<void> Function(ParentalConfig next) saveConfig;

  /// 本台设置保存（CR-02）：只提交 `mode / unlockMode / pin / activeChildIds`，
  /// 不提交 `children`——家庭模型下整份 parental 写入会覆盖该电视的档案分配。
  final Future<void> Function(ParentalConfig next) saveDeviceSettings;

  /// 下发解锁命令（补发 `parental_unlock`）。
  final Future<void> Function(RealtimeEvent event) unlock;

  /// 打开电视绑定管理底部弹层。
  final Future<void> Function() openDeviceManager;

  /// 打开「登录已有家长号」页（账号恢复主入口；重装/换手机凭家长号+口令找回）。
  final Future<void> Function() openLoginExisting;

  /// 打开「创建新家长号」页（首次使用 / 重装后无本地账号时）。
  final Future<void> Function() openCreateAccount;

  /// 本地是否已设置独立家长号（区别于设备派生号）。
  /// 未设置时各空态应优先引导「登录已有」或「创建新」家长号，而不是直接要求绑电视。
  final bool hasClaimedAccount;

  /// 下钻到某个全屏子页，返回后自动补拉事件。
  final Future<void> Function(Widget page) push;

  /// 向指定设备发送遥控命令。
  ///
  /// [to] 必须是「被点击那台」的派生号（家长端可有多台电视，不能写死当前
  /// 配置目标），命令由面板回调在闭包里固化后传入。
  final Future<void> Function(String to, String command) sendRemoteCommand;

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

  /// 打开某台电视的「档案共享」页（从「我的」进入）。
  final void Function(ParentalMachine machine) openShareManagement;

  /// 读取某台电视的共享视图（主本 / 引用 / 候选）。
  final Future<ParentalShareView> Function(ParentalMachine machine) loadShareView;

  /// 设置本台主本档案的分享白名单；返回服务端最新共享视图。
  final Future<ParentalShareView> Function(
    ParentalMachine machine,
    ParentalShareMaster child,
    List<String> sharedTo,
  ) setSharedTo;

  /// 引用一个可见主本档案；返回服务端最新共享视图。
  final Future<ParentalShareView> Function(
    ParentalMachine machine,
    ParentalShareCandidate candidate,
  ) addSharedRef;

  /// 取消一条引用（含 broken 占位）；返回服务端最新共享视图。
  final Future<ParentalShareView> Function(
    ParentalMachine machine,
    ParentalShareImported item,
  ) cancelSharedRef;
}
