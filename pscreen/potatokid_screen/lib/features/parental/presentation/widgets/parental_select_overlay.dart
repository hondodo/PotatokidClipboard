import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pscreen_screen/core/parental/parental_config.dart';
import 'package:pscreen_screen/core/parental/parental_state_controller.dart';

import 'parental_verification_sheet.dart';

/// 儿童模式开机选人页（阶段 3，全屏不透明覆盖层形态）。
///
/// 形态取舍：与 [ParentalLockOverlay] 一样挂在 `MainApp` 外层 Stack
/// （内容 → 消息浮层 → **本层** → 锁屏层），而非 Navigator 路由——
/// 路由会盖住锁屏层，开机同时「已到阈值锁屏 + 待选人」时层级会错；
/// 覆盖层可精确控制「锁屏在选人页之上」。
///
/// 触发与生命周期（方案 §2.2 选人流程）：
/// - 展示判定 = 生效判定式（`mode=='on' && children` 非空，配置来自
///   服务端 config 或本地缓存兜底）**且**（本次启动尚未确认过 **或**
///   已选档案全部悬空）——每次启动只确认一次，运行中不重复弹；
/// - 未确认前全屏遮挡（未确定不进直播）；确认后收起，判定式不再成立
///   （管理端关模式）即时收起；
/// - 预选 = 上次确认的选择（`activeChildIds`，悬空已过滤），缺省时即
///   服务端配置里的默认预选；
/// - 勾选 `locked` 档案先过 [ParentalVerificationSheet] 家长验证；
/// - 确认 → `setActiveChildren`（驱动计时分账 + 上报
///   `parental_child_active`，由 MsgModule 注入的回调发事件）。
///
/// 按键：本层不抢焦点（整层 `ExcludeFocus`），遥控按键统一由
/// `MainApp._handleLogical` 的闸门转发到 [handleKey]（与消息浮层同机制，
/// 焦点留在底层内容区，事件冒泡经根 Focus 被闸门截获）。
class ParentalSelectOverlay extends StatefulWidget {
  const ParentalSelectOverlay({super.key});

  /// 当前挂载的 State（`MainApp` 按键闸门用；未挂载时为 null）。
  static ParentalSelectOverlayState? _instance;

  /// 选人页是否可见（按键闸门读取）。
  static bool get gateVisible => _instance?._visible ?? false;

  /// 消费一个遥控按键；可见时恒吞掉（防止底层直播/导航被操作）。
  static bool handleGateKey(BuildContext context, LogicalKeyboardKey key) =>
      _instance?.handleKey(context, key) ?? false;

  @override
  State<ParentalSelectOverlay> createState() => ParentalSelectOverlayState();
}

class ParentalSelectOverlayState extends State<ParentalSelectOverlay> {
  /// 配置 / 选人状态变化（判定式、悬空过滤、换档案）→ 重新评估展示。
  final ParentalStateController _parental = ParentalStateController.instance;

  /// 本次启动是否已确认过（每次启动只弹一次）。
  bool _confirmed = false;

  /// 当前展示态（由 [_revalidate] 维护，按键闸门经 State 静态面读取）。
  bool _visible = false;

  /// 当前展示周期内选择态是否已从控制器同步（收起后复位，下次展示重同步）。
  bool _synced = false;

  /// 勾选中的档案 id。
  final Set<String> _checked = <String>{};

  /// 光标位置：`0..children.length-1` 为档案行，`children.length` 为「确定」。
  int _cursor = 0;

  /// 家长验证弹窗进行中（此期间只吞键不动作）。
  bool _awaitingVerify = false;

  @override
  void initState() {
    super.initState();
    ParentalSelectOverlay._instance = this;
    // 首帧直接评估（DI 已 await ensureLoaded，缓存配置就绪），再挂监听。
    _visible = _computeVisible();
    if (_visible) _syncSelection();
    _parental.addListener(_revalidate);
  }

  @override
  void dispose() {
    if (identical(ParentalSelectOverlay._instance, this)) {
      ParentalSelectOverlay._instance = null;
    }
    _parental.removeListener(_revalidate);
    super.dispose();
  }

  /// 展示判定：生效判定式 + 每次启动确认一次 + 已选全部悬空回退选人页。
  bool _computeVisible() {
    final ParentalConfig config = _parental.config;
    if (!config.enabled) return false; // 判定式不再成立 → 即时解除
    return !_confirmed || _parental.activeChildIds.isEmpty;
  }

  /// 配置/选人变化：维护展示态与选择态同步。
  void _revalidate() {
    final bool show = _computeVisible();
    if (show) {
      if (!_synced) _syncSelection();
    } else {
      _synced = false;
    }
    if (show != _visible) {
      setState(() => _visible = show);
    }
  }

  /// 同步预选：上次确认的选择（getter 已过滤悬空 id）。
  void _syncSelection() {
    _checked
      ..clear()
      ..addAll(_parental.activeChildIds);
    _cursor = 0;
    _synced = true;
  }

  /// 遥控按键入口（`MainApp._handleLogical` 闸门转发）；可见时恒返回 true。
  bool handleKey(BuildContext context, LogicalKeyboardKey key) {
    if (!_visible) return false;
    if (_awaitingVerify) return true; // 验证弹窗期间只吞键
    final int itemCount = _parental.config.children.length; // 档案数
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      final int delta = key == LogicalKeyboardKey.arrowUp ? -1 : 1;
      setState(() {
        final int total = itemCount + 1; // 档案 + 确定按钮
        _cursor = (_cursor + delta + total) % total;
      });
      return true;
    }
    final bool ok = key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.gameButtonA;
    if (ok) {
      if (_cursor >= itemCount) {
        unawaited(_confirm());
      } else if (_cursor < itemCount) {
        final ChildProfile profile = _parental.config.children[_cursor];
        unawaited(_toggle(context, profile));
      }
      return true;
    }
    // 返回 / 菜单 / 数字 / 左右：一律吞掉——未确定不退出、不操作底层。
    return true;
  }

  /// 勾选 / 取消勾选档案；`locked` 档案勾选前先过家长验证。
  Future<void> _toggle(BuildContext context, ChildProfile profile) async {
    if (_checked.contains(profile.id)) {
      setState(() => _checked.remove(profile.id));
      return;
    }
    if (profile.locked) {
      _awaitingVerify = true;
      final bool ok = await ParentalVerificationSheet.show(context);
      _awaitingVerify = false;
      if (!ok || !mounted) return;
    }
    setState(() => _checked.add(profile.id));
  }

  /// 确认进入直播：至少勾选一位；再滤一次悬空（配置可能在展示期间变更，
  /// 全部悬空则不能确认、留在选人页）；随后驱动计时分账并上报
  /// `parental_child_active`（MsgModule 注入的回调发事件）。
  Future<void> _confirm() async {
    if (_checked.isEmpty || _awaitingVerify) return;
    final List<String> ids =
        _parental.config.resolveActiveChildIds(_checked);
    if (ids.isEmpty) return;
    await _parental.setActiveChildren(ids);
    if (!mounted) return;
    setState(() => _confirmed = true);
    _revalidate(); // 收起（判定式仍成立但本次已确认）
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    final ParentalConfig config = _parental.config;
    final TextTheme textTheme = Theme.of(context).textTheme;
    // 整层排除焦点：点击不把焦点拉进本层，遥控按键始终经 main_app 闸门
    // （焦点留在底层内容区，事件冒泡被截获），两条路径不会打架。
    return ExcludeFocus(
      child: ColoredBox(
        color: Colors.black,
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      Icons.supervised_user_circle_outlined,
                      size: 64,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '请选择观看的孩子',
                      style: textTheme.headlineSmall
                          ?.copyWith(color: Colors.white),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '勾选一位或多位，按「确定」开始观看',
                      style: textTheme.bodyMedium
                          ?.copyWith(color: Colors.white70),
                    ),
                    const SizedBox(height: 16),
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            for (int i = 0;
                                i < config.children.length;
                                i++)
                              _buildRow(context, config.children[i], i),
                            const SizedBox(height: 8),
                            _buildConfirmRow(config),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 档案行：勾选框 + 名称 + 档位/受保护标签（光标行高亮）。
  Widget _buildRow(BuildContext context, ChildProfile profile, int index) {
    final bool checked = _checked.contains(profile.id);
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => unawaited(_toggle(context, profile)),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: _cursor == index
              ? scheme.primary.withValues(alpha: 0.25)
              : Colors.white10,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _cursor == index ? scheme.primary : Colors.white24,
          ),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              checked ? Icons.check_box : Icons.check_box_outline_blank,
              color: checked ? scheme.primary : Colors.white54,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                profile.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 18),
              ),
            ),
            if (profile.locked) ...<Widget>[
              const SizedBox(width: 8),
              Tooltip(
                message: '需家长验证',
                child: Icon(Icons.lock_outline,
                    size: 18, color: Colors.amber.shade700),
              ),
            ],
            const SizedBox(width: 8),
            Text(
              profile.isStrict ? '严格' : '温和',
              style: const TextStyle(color: Colors.white54, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  /// 「确定」行：光标行高亮；未勾选任何档案时置灰提示。
  Widget _buildConfirmRow(ParentalConfig config) {
    final int confirmIndex = config.children.length;
    final bool enabled = _checked.isNotEmpty;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? () => unawaited(_confirm()) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: !enabled
              ? Colors.white10
              : _cursor == confirmIndex
                  ? scheme.primary
                  : scheme.primary.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _cursor == confirmIndex ? Colors.white : scheme.primary,
            width: _cursor == confirmIndex ? 2 : 1,
          ),
        ),
        child: Center(
          child: Text(
            enabled ? '确定（已选 ${_checked.length} 位）' : '请至少勾选一位',
            style: const TextStyle(color: Colors.white, fontSize: 18),
          ),
        ),
      ),
    );
  }
}
