import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pscreen_screen/core/parental/child_avatar.dart';
import 'package:pscreen_screen/core/parental/parental_config.dart';
import 'package:pscreen_screen/core/parental/parental_state_controller.dart';

import 'parental_verification_sheet.dart';

/// 儿童模式开机选人页（阶段 3，全屏不透明覆盖层形态）——**电视端重设计版**。
///
/// 与旧版的区别（基因从「企业后台表单」换成「客厅 10-foot UI」）：
/// - 视觉：巨大圆角头像卡片（320×400，圆角 40），焦点态 scale 1.08 + 发光 shadow；
/// - 文案：「今天是谁在看电视呢？」为主标题，无副标题；
/// - 交互：卡片横向排列，←/→ 循环切卡，↑ 跳到确认按钮，OK 卡片上 = 切换勾选，
///   按钮上 = 确认；保留两步选择（勾选 + 确认），支持多孩一起看；
/// - 信息：卡片上只放头像 + 名字，档位/locked 改右下角小徽标，不再显「温和/严格」。
///
/// 触发与生命周期（与旧版一致）：
/// - 展示判定 = 生效判定式（`mode=='on' && children` 非空）**且**（本次启动尚未确认
///   过 **或** 已选档案全部悬空）——每次启动只确认一次；
/// - 未确认前全屏遮挡；确认后收起；配置侧关模式 → 即时收起；
/// - 预选 = 上次的选择（`activeChildIds`，悬空已过滤）；
/// - `locked` 档案勾选前过家长验证；
/// - 确认 → `setActiveChildren`（驱动计时分账 + 上报）。
///
/// 按键：本层不抢焦点（整层 `ExcludeFocus`），遥控按键由 `MainApp._handleLogical`
/// 闸门统一转发到 [handleKey]（与消息浮层同机制，事件冒泡经根 Focus 被闸门截获）。
class ParentalSelectOverlay extends StatefulWidget {
  const ParentalSelectOverlay({super.key});

  static ParentalSelectOverlayState? _instance;

  /// 选人页是否可见（按键闸门读取）。
  static bool get gateVisible => _instance?._visible ?? false;

  /// 消费一个遥控按键；可见时恒返回 true。
  static bool handleGateKey(BuildContext context, LogicalKeyboardKey key) =>
      _instance?.handleKey(context, key) ?? false;

  @override
  State<ParentalSelectOverlay> createState() => ParentalSelectOverlayState();
}

class ParentalSelectOverlayState extends State<ParentalSelectOverlay> {
  final ParentalStateController _parental = ParentalStateController.instance;
  final ScrollController _cardScrollController = ScrollController();

  /// 本次启动是否已确认过（每次启动只弹一次）。
  bool _confirmed = false;

  /// 「开播啦！」浮现（已按下确认但尚未收起，让用户看到反馈）。
  bool _launching = false;

  bool _visible = false;
  bool _synced = false;

  /// 勾选中的档案 id（可多位一起看）。
  final Set<String> _checked = <String>{};

  /// 光标位置：`0..children.length-1` 是卡片，`children.length` 是确认按钮。
  int _cursor = 0;

  bool _awaitingVerify = false;

  double _layoutScale = 1;

  @override
  void initState() {
    super.initState();
    ParentalSelectOverlay._instance = this;
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
    _cardScrollController.dispose();
    super.dispose();
  }

  bool _computeVisible() {
    final ParentalConfig config = _parental.config;
    if (!config.enabled) return false;
    return !_confirmed || _parental.activeChildIds.isEmpty;
  }

  void _revalidate() {
    final bool show = _computeVisible();
    if (show) {
      if (!_synced) _syncSelection();
    } else {
      _synced = false;
    }
    if (show != _visible) {
      setState(() {
        _visible = show;
        if (!show) _launching = false;
      });
    }
  }

  void _syncSelection() {
    _checked
      ..clear()
      ..addAll(_parental.activeChildIds);
    // 焦点停在已选里的第一位；全悬空时落在第一张卡。
    final List<String> active = _checked.toList();
    final int itemCount = _parental.config.children.length;
    if (itemCount > 0 && active.isNotEmpty) {
      final int idx = _parental.config.children.indexWhere((ChildProfile c) => c.id == active.first);
      _cursor = idx < 0 ? 0 : idx;
    } else {
      _cursor = 0;
    }
    _synced = true;
  }

  /// 遥控按键入口（闸门转发）。
  bool handleKey(BuildContext context, LogicalKeyboardKey key) {
    if (!_visible) return false;
    if (_awaitingVerify || _launching) return true;
    final List<ChildProfile> children = _parental.config.children;
    final int itemCount = children.length;
    if (itemCount == 0) return true;
    final int total = itemCount + 1; // 档案 + 确认按钮

    // 卡片间左右循环；按钮 ←/→ 跳回第一张卡。
    if (key == LogicalKeyboardKey.arrowLeft) {
      setState(() {
        if (_cursor >= itemCount) {
          _cursor = itemCount - 1;
        } else {
          _cursor = (_cursor - 1 + itemCount) % itemCount;
        }
      });
      _scrollFocusedCardIntoView(itemCount);
      return true;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      setState(() {
        if (_cursor >= itemCount) {
          _cursor = 0;
        } else {
          _cursor = (_cursor + 1) % itemCount;
        }
      });
      _scrollFocusedCardIntoView(itemCount);
      return true;
    }
    // ↑ 按钮 → 最后一张卡；卡 → 确认按钮。
    if (key == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _cursor = (_cursor + total - 1) % total;
      });
      _scrollFocusedCardIntoView(itemCount);
      return true;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _cursor = (_cursor + 1) % total;
      });
      _scrollFocusedCardIntoView(itemCount);
      return true;
    }

    final bool ok =
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.gameButtonA;
    if (ok) {
      if (_cursor >= itemCount) {
        unawaited(_confirm());
      } else {
        unawaited(_toggle(context, children[_cursor]));
      }
      return true;
    }
    // 返回 / 菜单 / 数字：一律吞掉——未确定不退出、不操作底层。
    return true;
  }

  void _scrollFocusedCardIntoView(int itemCount) {
    if (itemCount <= 4 || _cursor >= itemCount) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_cardScrollController.hasClients) return;
      final ScrollPosition position = _cardScrollController.position;
      final double cardWidth = 220 * _layoutScale;
      final double itemExtent = 240 * _layoutScale;
      final double leadingPadding = 48 * _layoutScale;
      final double target = leadingPadding + _cursor * itemExtent - (position.viewportDimension - cardWidth) / 2;
      _cardScrollController.animateTo(
        target.clamp(position.minScrollExtent, position.maxScrollExtent),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

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

  Future<void> _confirm() async {
    if (_checked.isEmpty || _awaitingVerify) return;
    final List<String> ids = _parental.config.resolveActiveChildIds(_checked);
    if (ids.isEmpty) return;
    setState(() => _launching = true);
    await _parental.setActiveChildren(ids);
    if (!mounted) return;
    // 留一点时间让「开播啦！」浮现出来再收起。
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    setState(() => _confirmed = true);
    _revalidate();
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();

    return ExcludeFocus(
      child: ColoredBox(
        // 深色底 + 两团大柔光（静态渐变，不调用 BackdropFilter）。
        color: const Color(0xFF0B1020),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[Color(0xFF111633), Color(0xFF050818)],
            ),
          ),
          child: SafeArea(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints viewport) {
                final double vw = viewport.maxWidth;
                final double vh = viewport.maxHeight;
                final int cardCount = _parental.config.children.length;

                // --- 所有基准值都是"安全偏小"版 ---
                // 卡片 220×300 / 卡片安全区 332 / padding 40 / 头像 150 / 标题 44
                // 总高按标题、两段间距、焦点放大安全区和最高 footer 估算，
                // 额外保留阴影余量，避免 720p 下内容显得拥挤。
                const double baseTotalH = 780.0;
                final double hScale = vh / baseTotalH;

                // 宽度：padH*2 + N*220 + (N-1)*20 + 15% 余量
                final int rowCards = math.min(cardCount, 4);
                final double rawW = rowCards > 0 ? (80.0 + 220.0 * rowCards + 20.0 * (rowCards - 1)) : 80.0;
                final double wScale = vw / (rawW * 1.15);

                final double viewScale = math.min(vh / 540.0, vw / 960.0);

                final double scale = math.min(math.min(hScale, wScale), viewScale).clamp(0.4, 1.4);
                _layoutScale = scale;

                return _buildOverlayBody(context, viewport, scale);
              },
            ),
          ),
        ),
      ),
    );
  }

  /// 把原来的 Stack 主体抽成独立方法，接收 scale（适配 720p / 1080p / 4K）。
  Widget _buildOverlayBody(BuildContext context, BoxConstraints viewport, double scale) {
    final ParentalConfig config = _parental.config;
    final TextTheme textTheme = Theme.of(context).textTheme;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final List<ChildProfile> children = config.children;

    // 所有尺寸都从 1080p 基准按 scale 缩放。
    final double padH = 40 * scale;
    final double padV = 32 * scale;
    final double titleFont = 44 * scale;
    final double gapTitleCards = 36 * scale;
    final double gapCardsFooter = 32 * scale;
    final double glowSizeA = 400 * scale;
    final double glowSizeB = 440 * scale;
    final double glowNegTop = 80 * scale;
    final double glowNegLeft = 120 * scale;
    final double glowNegBottom = 120 * scale;
    final double glowNegRight = 80 * scale;

    return Stack(
      children: <Widget>[
        Positioned(
          top: -glowNegTop,
          left: -glowNegLeft,
          child: Container(
            width: glowSizeA,
            height: glowSizeA,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: <Color>[scheme.primary.withValues(alpha: 0.18), scheme.primary.withValues(alpha: 0)],
              ),
            ),
          ),
        ),
        Positioned(
          bottom: -glowNegBottom,
          right: -glowNegRight,
          child: Container(
            width: glowSizeB,
            height: glowSizeB,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: <Color>[Colors.pinkAccent.withValues(alpha: 0.12), Colors.pinkAccent.withValues(alpha: 0)],
              ),
            ),
          ),
        ),
        Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  '今天是谁在看电视呢？',
                  textAlign: TextAlign.center,
                  style: textTheme.headlineMedium?.copyWith(
                    color: Colors.white,
                    fontSize: titleFont,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  ),
                ),
                SizedBox(height: gapTitleCards),
                _buildCardRow(children, scheme, scale),
                SizedBox(height: gapCardsFooter),
                Align(alignment: Alignment.center, child: _buildFooter(children, scheme, scale)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 卡片横排：≤4 张时全部展示并排居中；>4 张留横向滚动空间。
  Widget _buildCardRow(List<ChildProfile> children, ColorScheme scheme, double scale) {
    if (children.isEmpty) return const SizedBox.shrink();
    if (children.length <= 4) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 16 * scale),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: List<Widget>.generate(children.length, (int i) {
              return Padding(
                padding: EdgeInsets.symmetric(horizontal: 10 * scale),
                child: _buildCard(children[i], i, scheme, scale),
              );
            }),
          ),
        ),
      );
    }
    return SizedBox(
      height: 332 * scale,
      child: ListView.separated(
        controller: _cardScrollController,
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: 48 * scale, vertical: 16 * scale),
        itemCount: children.length,
        separatorBuilder: (_, _) => SizedBox(width: 20 * scale),
        itemBuilder: (BuildContext context, int index) {
          return _buildCard(children[index], index, scheme, scale);
        },
      ),
    );
  }

  /// 单张头像卡片：圆角 40 + 焦点 scale 1.08 + 发光 shadow + 勾选徽标 + locked 徽标。
  Widget _buildCard(ChildProfile profile, int index, ColorScheme scheme, double scale) {
    final bool focused = _cursor == index;
    final bool checked = _checked.contains(profile.id);
    // 焦点态 scale + 亮度；非焦点暗一点、缩小一点。
    final double cardScale = focused ? 1.08 : (checked ? 1.0 : 0.92);
    final double opacity = focused ? 1.0 : (checked ? 1.0 : 0.62);
    final bool locked = profile.locked;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        // 触屏点击 → 聚焦 + 触发和遥控 OK 完全相同的勾选逻辑。
        setState(() => _cursor = index);
        unawaited(_toggle(context, _parental.config.children[index]));
      },
      onTapDown: (_) => setState(() => _cursor = index),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 180),
        scale: cardScale,
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: opacity,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 220 * scale,
            height: 300 * scale,
            decoration: BoxDecoration(
              color: focused ? scheme.primary.withValues(alpha: 0.22) : Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(32 * scale),
              border: Border.all(
                color: focused
                    ? Colors.white
                    : (checked ? scheme.primary.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.12)),
                width: (focused ? 3 : (checked ? 2 : 1)) * scale,
              ),
              boxShadow: focused
                  ? <BoxShadow>[
                      BoxShadow(
                        color: scheme.primary.withValues(alpha: 0.5),
                        blurRadius: 32 * scale,
                        spreadRadius: 2 * scale,
                      ),
                      BoxShadow(color: scheme.primary.withValues(alpha: 0.25), blurRadius: 64 * scale),
                    ]
                  : <BoxShadow>[BoxShadow(color: Colors.black38, blurRadius: 12 * scale, offset: Offset(0, 6 * scale))],
            ),
            child: Stack(
              children: <Widget>[
                Padding(
                  padding: EdgeInsets.fromLTRB(20 * scale, 20 * scale, 20 * scale, 16 * scale),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Expanded(
                        flex: 7,
                        child: Center(
                          child: Container(
                            width: 150 * scale,
                            height: 150 * scale,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: <Color>[
                                  scheme.primary.withValues(alpha: 0.55),
                                  scheme.primary.withValues(alpha: 0.1),
                                ],
                              ),
                            ),
                            child: Padding(
                              padding: EdgeInsets.all(6 * scale),
                              child: ClipOval(
                                child: ChildAvatarWidget(
                                  avatar: profile.avatar,
                                  width: double.infinity,
                                  height: double.infinity,
                                  fallback: Container(
                                    width: double.infinity,
                                    height: double.infinity,
                                    color: scheme.primary.withValues(alpha: 0.2),
                                    alignment: Alignment.center,
                                    child: Text(
                                      profile.name.isNotEmpty ? profile.name.characters.first : '?',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 66 * scale,
                                        fontWeight: FontWeight.w700,
                                        height: 1.0,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Flexible(
                        flex: 2,
                        child: Center(
                          child: Text(
                            profile.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 24 * scale,
                              fontWeight: FontWeight.w600,
                              height: 1.2,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (checked)
                  Positioned(
                    top: 16 * scale,
                    right: 16 * scale,
                    child: Container(
                      width: 40 * scale,
                      height: 40 * scale,
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        shape: BoxShape.circle,
                        boxShadow: <BoxShadow>[
                          BoxShadow(color: Colors.black54, blurRadius: 8 * scale, offset: Offset(0, 2 * scale)),
                        ],
                      ),
                      child: Icon(Icons.check, color: Colors.white, size: 24 * scale),
                    ),
                  ),
                // 右下角：锁定徽标（仅当 locked）。
                if (locked)
                  Positioned(
                    bottom: 16 * scale,
                    right: 16 * scale,
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 6 * scale),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(14 * scale),
                      ),
                      child: Icon(Icons.lock_outline, color: Colors.black54, size: 18 * scale),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 底部：未选时灰色引导 + 呼吸图标；选了后「开播啦！」大按钮；确认中「开播啦！」浮现。
  Widget _buildFooter(List<ChildProfile> children, ColorScheme scheme, double scale) {
    final int buttonIndex = children.length;
    final bool focused = _cursor == buttonIndex;
    final bool enabled = _checked.isNotEmpty;

    if (_launching) {
      return AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: EdgeInsets.symmetric(horizontal: 64 * scale, vertical: 24 * scale),
        decoration: BoxDecoration(
          color: scheme.primary,
          borderRadius: BorderRadius.circular(24 * scale),
          boxShadow: <BoxShadow>[
            BoxShadow(color: scheme.primary.withValues(alpha: 0.6), blurRadius: 32 * scale, spreadRadius: 4 * scale),
          ],
        ),
        child: Text(
          '开播啦！',
          style: TextStyle(color: Colors.white, fontSize: 28 * scale, fontWeight: FontWeight.w700),
        ),
      );
    }

    if (!enabled) {
      // 未选：灰色引导 + 呼吸遥控器图标。Row 在窄屏上会溢出，
      // 用 Flexible 让 Text 可以缩行；引导语在 720p TV 上缩成两行也不丑。
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.keyboard, color: Colors.white54, size: 24 * scale),
          SizedBox(width: 10 * scale),
          Flexible(
            child: Text(
              '用遥控器选择头像，按 OK 勾选 · 再按 OK 开始观看',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 22 * scale),
            ),
          ),
        ],
      );
    }

    // 已选：浮动「开始观看（已选 N 位）」按钮。
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled
          ? () {
              setState(() => _cursor = buttonIndex);
              unawaited(_confirm());
            }
          : null,
      onTapDown: enabled ? (_) => setState(() => _cursor = buttonIndex) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.symmetric(horizontal: 36 * scale, vertical: 16 * scale),
        decoration: BoxDecoration(
          color: !enabled
              ? Colors.white10
              : focused
              ? scheme.primary
              : scheme.primary.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(24 * scale),
          border: Border.all(color: focused ? Colors.white : scheme.primary, width: (focused ? 3 : 1) * scale),
          boxShadow: focused
              ? <BoxShadow>[
                  BoxShadow(
                    color: scheme.primary.withValues(alpha: 0.55),
                    blurRadius: 28 * scale,
                    spreadRadius: 2 * scale,
                  ),
                ]
              : null,
        ),
        child: Text(
          '开始观看（已选 ${_checked.length} 位）',
          style: TextStyle(color: Colors.white, fontSize: 28 * scale, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
