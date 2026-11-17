import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pscreen_home/core/di/get_it.dart';
import 'package:pscreen_home/core/storage/settings_store.dart';
import 'package:pscreen_home/features/screen/presentation/components/live_player_view.dart';
import 'package:pscreen_screen/core/media/sleep_timer_controller.dart';
import 'package:pscreen_screen/features/iptv/application/bloc/iptv_bloc.dart';
import 'package:pscreen_screen/features/iptv/application/bloc/iptv_event.dart';
import 'package:pscreen_screen/features/iptv/application/bloc/iptv_state.dart';
import 'package:pscreen_screen/features/iptv/application/live_channel_controller.dart';
import 'package:pscreen_screen/features/iptv/application/recording/recording_controller.dart';
import 'package:pscreen_screen/features/iptv/application/recording/recording_source_provider.dart';
import 'package:pscreen_screen/features/iptv/domain/models/iptv_channel.dart';

/// 直播页：播放器铺满整个 body，频道列表是 [Stack] 上层的右侧浮层。
///
/// 交互：
/// - 进入页面 → 默认全屏（隐藏 AppBar），右侧列表自动显示，
///   并开始 [LivePage._hideDelay] 倒计时；
/// - 倒计时内无操作 → 列表自动隐藏；
/// - 显示期间任何操作（点频道 / 点全屏或恢复 / 点上一台 / 点下一台）→ 重新计时；
/// - 点「列表与底部按钮之外」的播放器空白处 → 显示 ⇄ 隐藏 切换；
/// - 底部「全屏 / 恢复」「上一台 / 下一台」按钮居中，与列表同层，一起跟随显隐，
///   列表停靠右边不会遮住它们；
/// - 全屏时隐藏 AppBar，让播放器铺满整个页面；左上角保留一个
///   [Stack] 内的返回按钮，仍可退出直播页回主控页；
/// - 点「恢复」→ 重新显示 AppBar；
/// - [floating] 为 true 时只渲染播放器（全局宿主负责小窗尺寸、拖动和单击
///   回全屏），底部控制条隐藏，但播放器仍是同一个 State，不会中断。
class LivePage extends StatefulWidget {
  const LivePage({super.key, this.enablePlayer = true, this.floating = false, this.onFloat, this.onClose});

  /// 是否实例化真实播放器（测试环境置 false）。
  final bool enablePlayer;

  /// 是否处于应用内悬浮小窗形态。
  final bool floating;

  /// 点击「悬浮」按钮：交给全局直播宿主缩小成小窗。
  final VoidCallback? onFloat;

  /// 关闭直播；为空时退回路由返回（保留 LivePage 单独使用的兼容性）。
  final VoidCallback? onClose;

  @override
  State<LivePage> createState() => _LivePageState();
}

class _LivePageState extends State<LivePage> {
  /// 无操作多久后自动隐藏浮层。
  static const Duration _hideDelay = Duration(seconds: 10);

  /// 右侧频道列表浮层宽度。
  static const double _listWidth = 320;

  /// 浮层（右侧列表 + 底部切台按钮）是否显示。
  bool _overlayVisible = true;

  /// 是否处于「隐藏 AppBar」的全屏模式（播放器占满整个页面）。
  /// 进入直播页默认全屏，让视频画面最大化。
  bool _fullscreen = true;

  /// 自动隐藏计时器。
  Timer? _hideTimer;

  /// 当前频道列表（保存 / 恢复上次频道时按序号取频道名）。
  List<IptvChannel> _channels = const <IptvChannel>[];

  /// 是否已尝试恢复上次频道；恢复完成前 [_channels] 就绪即可恢复。
  bool _restored = false;

  @override
  void initState() {
    super.initState();
    // 进入页面：浮层自动显示并开始倒计时。
    _scheduleHide();
    // 录制事件（切源被拒 / 已保存 / 不支持 / 失败）由本页统一提示（D-9）。
    RecordingController.instance.onEvent = _handleRecordingEvent;
  }

  @override
  void dispose() {
    if (RecordingController.instance.onEvent == _handleRecordingEvent) {
      RecordingController.instance.onEvent = null;
    }
    _hideTimer?.cancel();
    super.dispose();
  }

  /// 录制事件 → 中文 SnackBar（home 端无 i18n，文案硬编码中文）。
  void _handleRecordingEvent(RecordingEventData event) {
    if (!mounted) return;
    String? message;
    switch (event.type) {
      case RecordingEvent.started:
        message = '正在录制 ${event.channelName}';
      case RecordingEvent.saved:
        message = '已保存 ${event.channelName} 的录制';
      case RecordingEvent.unsupported:
        message = '该频道加密，无法录制';
      case RecordingEvent.failed:
        message = '录制失败，已保存部分内容';
      case RecordingEvent.switchBlocked:
        message = '录制中不能切换信号源，请先停止录制';
      case RecordingEvent.sourceSwitched:
        message = '信号源已自动切换，录制已保存';
      case RecordingEvent.lowSpace:
        message = '存储空间不足，录制已停止';
      case RecordingEvent.duplicate:
        return; // 互斥由按钮状态体现，不重复弹提示。
    }
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  /// 录制按钮点击：切换开始/停止。当前源取播放器上报的原始源。
  Future<void> _toggleRecording() async {
    final RecordingController controller = RecordingController.instance;
    if (controller.isRecording) {
      await controller.stop();
      return;
    }
    final RecordingSource? source = RecordingSourceProvider.instance.current;
    if (source == null) {
      controller.onEvent?.call(const RecordingEventData(RecordingEvent.failed));
      return;
    }
    await controller.start(source);
  }

  /// 设置存储；widget 测试未初始化 DI 时为 null（跳过，不影响播放）。
  SettingsStore? get _settingsStore => getIt.isRegistered<SettingsStore>() ? getIt<SettingsStore>() : null;

  /// 频道列表就绪后恢复上次观看的频道（按频道名匹配，找不到则保持第 0 台）。
  ///
  /// 只负责「读回上次频道」；「记住当前频道」已下沉到播放器提交路径
  /// （LivePlayerView._openCurrent），与电视端 onPlayCommit 模式一致——
  /// 这样遥控选台也能落盘，避免下次恢复读回旧频道。
  void _restoreLastChannel() {
    if (_restored || _channels.isEmpty) return;
    _restored = true;
    final String saved = _settingsStore?.lastLiveChannel ?? '';
    if (saved.isEmpty) return;
    final int index = _channels.indexWhere((IptvChannel c) => c.name == saved);
    if (index < 0) return;
    LiveChannelController.instance.select(index);
  }

  /// 重新开始「无操作 N 秒后隐藏」的倒计时。
  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(_hideDelay, () {
      if (!mounted) return;
      setState(() => _overlayVisible = false);
    });
  }

  /// 点播放器空白处（列表与底部按钮之外）：显示 ⇄ 隐藏 切换。
  void _toggleOverlay() {
    setState(() => _overlayVisible = !_overlayVisible);
    if (_overlayVisible) {
      _scheduleHide();
    } else {
      _hideTimer?.cancel();
    }
  }

  /// 切换「全屏 / 恢复」：全屏时隐藏 AppBar，播放器向上铺满；
  /// 恢复时重新显示 AppBar。
  void _toggleFullscreen() {
    setState(() => _fullscreen = !_fullscreen);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      // 全屏模式下不传 appBar：body 直接铺到页面顶部，视频画面更大。
      // 左上角的返回按钮由 body 内的 [Stack] 提供，仍可退出直播页。
      // 悬浮小窗也不需要 AppBar / 刷新按钮。
      appBar: widget.floating || _fullscreen
          ? null
          : AppBar(
              title: const Text('直播'),
              actions: <Widget>[
                IconButton(
                  tooltip: '刷新',
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: () => context.read<IptvBloc>().add(const LoadIptv(isRefresh: true)),
                ),
              ],
            ),
      body: BlocConsumer<IptvBloc, IptvState>(
        listener: (BuildContext context, IptvState state) {
          // 共享包的频道控制器按「频道总数」判断 select/next 是否有效，
          // 这里同步一次，触屏点选才能立即切台。
          // 放在 listener（状态变化时）而不是 build：build 阶段的副作用会
          // 在重建中触发 notifyListeners，导致不必要的重绘。
          _channels = state.channels;
          LiveChannelController.instance.setCount(state.channels.length);
          // 首次拿到频道列表时恢复上次观看的频道。
          _restoreLastChannel();
        },
        builder: (BuildContext context, IptvState state) {
          if (state.isLoading && state.channels.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('正在获取频道列表…', style: TextStyle(color: Colors.white)),
                ],
              ),
            );
          }
          if (state.errorMessage != null && state.channels.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      state.errorMessage!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    autofocus: true,
                    onPressed: () => context.read<IptvBloc>().add(const LoadIptv(isRefresh: true)),
                    child: const Text('重试'),
                  ),
                ],
              ),
            );
          }
          final List<IptvChannel> channels = state.channels;
          final bool floating = widget.floating;
          // 点「列表与底部按钮之外」的播放器空白区，切换浮层显隐。
          // 列表面板 / 切台按钮自带点击处理，会吃掉各自区域的点按，
          // 不会冒泡到这里触发切换。
          //
          // 悬浮小窗不再吃 tap：单击由全局宿主接管（回全屏），
          // 拖动也由宿主处理；这里只负责把播放器画出来。
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: floating ? null : _toggleOverlay,
            child: Stack(
              children: <Widget>[
                // 播放器铺满整个区域，始终是 Stack 的第 0 个 child；
                // 全屏 ⇄ 悬浮切换时位置/尺寸变化，但播放器 State 不重建。
                Positioned.fill(
                  child: widget.enablePlayer && channels.isNotEmpty
                      ? LivePlayerView(channels: channels)
                      : const ColoredBox(
                          color: Colors.black,
                          child: Center(
                            child: Text('播放器', style: TextStyle(color: Colors.white38)),
                          ),
                        ),
                ),
                // 悬浮小窗空间小，倒计时收紧凑挂右上角；不拦截拖动/单击。
                if (floating) const Positioned(top: 8, right: 8, child: LiveSleepTimerBadge(compact: true)),
                // 悬浮小窗只显示画面 + 当前频道名；徽标不拦截手势，
                // 拖动 / 单击回全屏仍由全局宿主处理。
                if (floating && channels.isNotEmpty)
                  Positioned(
                    left: 8,
                    bottom: 8,
                    child: IgnorePointer(child: _ChannelNameBadge(channels: channels, compact: true)),
                  ),
                if (state.usingCachedList)
                  Positioned(
                    left: floating ? 8 : 12,
                    top: floating ? 8 : null,
                    bottom: floating ? null : 48,
                    child: const _CachedListNotice(),
                  ),
                if (!floating) ...<Widget>[
                  // 定时关闭倒计时：直播页没有 AppBar，单独挂在左上角
                  // （返回按钮右侧），且不跟随频道浮层自动隐藏。
                  Positioned(top: 12, left: _fullscreen ? 64 : 12, child: const LiveSleepTimerBadge()),
                  // 录制中角标（左下角频道名上方）：纯展示，不拦手势。
                  Positioned(left: 12, bottom: 64, child: _HomeRecordingIndicator()),
                  // 全屏模式左上角返回按钮：AppBar 已隐藏，仍可退出直播页回主控页。
                  if (_fullscreen)
                    Positioned(
                      top: 12,
                      left: 12,
                      child: Material(
                        color: Colors.black54,
                        shape: const CircleBorder(),
                        clipBehavior: Clip.antiAlias,
                        child: IconButton(
                          tooltip: '返回',
                          iconSize: 32,
                          color: Colors.white,
                          icon: const Icon(Icons.arrow_back_rounded),
                          onPressed: widget.onClose ?? () => Navigator.of(context).maybePop(),
                        ),
                      ),
                    ),
                  // 左下角当前频道名（始终显示，便于关掉浮层后仍知道在看什么）。
                  if (channels.isNotEmpty)
                    Positioned(left: 12, bottom: 12, child: _ChannelNameBadge(channels: channels)),
                  // 底部居中「悬浮」「全屏 / 恢复」「上一台 / 下一台」，
                  // 与列表同层，跟随显隐。
                  if (_overlayVisible && channels.isNotEmpty)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 12,
                      child: Center(
                        child: _ChannelSwitchControls(
                          onInteract: _scheduleHide,
                          fullscreen: _fullscreen,
                          onToggleFullscreen: _toggleFullscreen,
                          onFloat: widget.onFloat,
                          onToggleRecording: _toggleRecording,
                        ),
                      ),
                    ),
                  // 右侧频道列表浮层，跟随显隐。
                  if (_overlayVisible && channels.isNotEmpty)
                    Positioned(
                      top: 12,
                      bottom: 12,
                      right: 12,
                      width: _listWidth,
                      child: _ChannelListPanel(channels: channels, onInteract: _scheduleHide),
                    ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// 直播定时关闭倒计时角标（`⏱ 直播定时关闭 mm:ss`），未开启时隐藏。
///
/// 直播页没有 AppBar，无法复用首页的角标；这里直接监听全局
/// [SleepTimerController]，本机设置页或遥控下发都能立即看到剩余时间。
class LiveSleepTimerBadge extends StatelessWidget {
  const LiveSleepTimerBadge({super.key, this.compact = false});

  /// 悬浮小窗中使用更紧凑的字号/间距。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SleepTimerController.instance,
      builder: (BuildContext context, Widget? _) {
        final SleepTimerController timer = SleepTimerController.instance;
        if (!timer.active) return const SizedBox.shrink();
        return IgnorePointer(
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12, vertical: compact ? 4 : 6),
            decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.timer_outlined, size: compact ? 14 : 18, color: Colors.white70),
                const SizedBox(width: 6),
                Text(
                  //直播定时关闭
                  timer.remainingLabel,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: compact ? 12 : 14,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 拉取失败但本地有缓存时的轻提示：继续播放旧列表，不打断观看。
class _CachedListNotice extends StatelessWidget {
  const _CachedListNotice();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
        child: const Text(
          '当前使用的是上次的频道列表',
          style: TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ),
    );
  }
}

/// 录制中角标（红点 + mm:ss）：纯展示，IgnorePointer 不拦手势。
class _HomeRecordingIndicator extends StatelessWidget {
  const _HomeRecordingIndicator();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<RecordingState>(
      valueListenable: RecordingController.instance.state,
      builder: (context, state, _) {
        if (!state.isRecording) return const SizedBox.shrink();
        final int s = state.elapsed.inSeconds;
        final String mmss =
            '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
        return IgnorePointer(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xCC1A1A1A),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0x66FF5252)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.fiber_manual_record, color: Color(0xFFFF5252), size: 13),
                const SizedBox(width: 6),
                Text('录制中 $mmss', style: const TextStyle(color: Colors.white, fontSize: 13)),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 左下角当前频道名（始终显示）。
class _ChannelNameBadge extends StatelessWidget {
  const _ChannelNameBadge({required this.channels, this.compact = false});

  final List<IptvChannel> channels;

  /// 悬浮小窗中使用更紧凑的字号/间距。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: LiveChannelController.instance,
      builder: (BuildContext context, Widget? child) {
        final int index = LiveChannelController.instance.index;
        if (index < 0 || index >= channels.length) {
          return const SizedBox.shrink();
        }
        // 序号从 1 开始，按频道总数的位数左侧补零（与电视端规则一致：
        // 8 个频道→`1`，120 个→`001`）。
        final int total = channels.length;
        final int width = total <= 1 ? 1 : total.toString().length;
        final String number = (index + 1).toString().padLeft(width, '0');
        return Container(
          padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12, vertical: compact ? 4 : 6),
          decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
          child: Text(
            '$number ${channels[index].name}',
            style: TextStyle(
              color: Colors.white,
              fontSize: compact ? 13 : 20,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        );
      },
    );
  }
}

/// 底部居中「悬浮」「全屏 / 恢复」「上一台 / 下一台」：
/// 点击除了执行操作，还重置自动隐藏计时。
class _ChannelSwitchControls extends StatelessWidget {
  const _ChannelSwitchControls({
    required this.onInteract,
    required this.fullscreen,
    required this.onToggleFullscreen,
    this.onFloat,
    this.onToggleRecording,
  });

  /// 有操作时回调（用于重置自动隐藏计时）。
  final VoidCallback onInteract;

  /// 当前是否为「隐藏 AppBar」的全屏模式。
  final bool fullscreen;

  /// 切换全屏 / 恢复。
  final VoidCallback onToggleFullscreen;

  /// 缩小成应用内悬浮小窗；为空时不显示按钮（单独使用 LivePage 的测试）。
  final VoidCallback? onFloat;

  /// 开始/停止录制（由 LivePage 注入）。
  final VoidCallback? onToggleRecording;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(24),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (onFloat != null)
            IconButton(
              tooltip: '悬浮',
              iconSize: 36,
              color: Colors.white,
              icon: const Icon(Icons.picture_in_picture_alt_rounded),
              onPressed: () {
                onFloat!();
                onInteract();
              },
            ),
          IconButton(
            tooltip: fullscreen ? '恢复' : '全屏',
            iconSize: 36,
            color: Colors.white,
            icon: Icon(fullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded),
            onPressed: () {
              onToggleFullscreen();
              onInteract();
            },
          ),
          IconButton(
            tooltip: '上一台',
            iconSize: 36,
            color: Colors.white,
            icon: const Icon(Icons.skip_previous_rounded),
            onPressed: () {
              LiveChannelController.instance.previous();
              onInteract();
            },
          ),
          IconButton(
            tooltip: '下一台',
            iconSize: 36,
            color: Colors.white,
            icon: const Icon(Icons.skip_next_rounded),
            onPressed: () {
              LiveChannelController.instance.next();
              onInteract();
            },
          ),
          // 录制按钮：状态实时刷新图标/提示色，点击开始/停止当前频道录制。
          // 悬浮小窗（floating==true）不渲染本控制区，故不会显示此按钮。
          ValueListenableBuilder<RecordingState>(
            valueListenable: RecordingController.instance.state,
            builder: (context, recording, _) => IconButton(
              tooltip: recording.isRecording ? '停止录制' : '开始录制',
              iconSize: 36,
              color: recording.isRecording ? const Color(0xFFFF5252) : Colors.white,
              icon: Icon(
                recording.isRecording
                    ? Icons.stop_circle_outlined
                    : Icons.fiber_manual_record,
              ),
              onPressed: () {
                onToggleRecording?.call();
                onInteract();
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// 右侧频道列表浮层：点选切台，选中项高亮并自动滚动到可视区中部。
///
/// 上/下台或点选改变的是共享的 [LiveChannelController.index]，这里监听它：
/// - 列表随之滚动，保证当前频道始终可见（恢复上次频道时也会定位）；
/// - 高亮当前频道（白字加粗 + 播放标记 + 底色）。
/// 用户点选或滑动列表都会调用 [onInteract] 重置外层浮层的自动隐藏计时；
/// 程序化滚动（_scrollToSelected 的 jumpTo/animateTo）不算用户操作。
class _ChannelListPanel extends StatefulWidget {
  const _ChannelListPanel({required this.channels, required this.onInteract});

  final List<IptvChannel> channels;

  /// 用户操作（点选频道 / 滑动列表）后的回调（用于重置自动隐藏计时）。
  final VoidCallback onInteract;

  @override
  State<_ChannelListPanel> createState() => _ChannelListPanelState();
}

class _ChannelListPanelState extends State<_ChannelListPanel> {
  /// 单行固定高度：滚动定位按「序号 × 高度」计算，避免动态测量。
  static const double _itemExtent = 64;

  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    LiveChannelController.instance.addListener(_onSelectionChanged);
    // 首次布局后先定位到当前频道（恢复上次频道时列表不会停在顶部）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToSelected(animate: false);
    });
  }

  @override
  void dispose() {
    LiveChannelController.instance.removeListener(_onSelectionChanged);
    _scroll.dispose();
    super.dispose();
  }

  void _onSelectionChanged() {
    if (!mounted) return;
    setState(() {});
    _scrollToSelected(animate: true);
  }

  /// 把选中项滚动到可视区中部（首尾自动夹紧，不越界）。
  void _scrollToSelected({required bool animate}) {
    if (!mounted || !_scroll.hasClients) return;
    final int index = LiveChannelController.instance.index;
    if (index < 0 || index >= widget.channels.length) return;
    final ScrollPosition position = _scroll.position;
    final double target = (index * _itemExtent - (position.viewportDimension - _itemExtent) / 2).clamp(
      0.0,
      position.maxScrollExtent,
    );
    if (animate) {
      _scroll.animateTo(target, duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
    } else {
      _scroll.jumpTo(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    final int current = LiveChannelController.instance.index;
    return Material(
      color: Colors.black.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      // 用户滑动列表（手指拖动 / 滚轮 / 惯性）也算「有操作」，同样重置
      // 外层 10 秒自动隐藏计时；_scrollToSelected 的程序化定位不触发。
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScrollNotification,
        child: ListView.builder(
          controller: _scroll,
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemExtent: _itemExtent,
          itemCount: widget.channels.length,
          itemBuilder: (BuildContext context, int index) {
            final IptvChannel channel = widget.channels[index];
            final bool selected = index == current;
            // 序号从 1 开始，按频道总数的位数左侧补零（与电视端频道条一致）。
            final int total = widget.channels.length;
            final int numberWidth = total <= 1 ? 1 : total.toString().length;
            return ListTile(
              dense: true,
              // 序号列（右对齐、等宽数字），便于对照台号直选。
              leading: SizedBox(
                width: 34,
                child: Text(
                  (index + 1).toString().padLeft(numberWidth, '0'),
                  maxLines: 1,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: selected ? Colors.white : Colors.white60,
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                    fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
                  ),
                ),
              ),
              title: Text(
                channel.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white70,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
              subtitle: channel.group == null || channel.group!.isEmpty
                  ? null
                  : Text(
                      channel.group!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: selected ? Colors.white70 : Colors.white38),
                    ),
              trailing: selected ? const Icon(Icons.play_arrow_rounded, size: 20, color: Colors.white) : null,
              selected: selected,
              selectedTileColor: Colors.white24,
              onTap: () {
                LiveChannelController.instance.select(index);
                widget.onInteract();
              },
            );
          },
        ),
      ),
    );
  }

  /// 用户滚动列表时重置外层的自动隐藏计时；程序化定位不算用户操作。
  bool _onScrollNotification(ScrollNotification notification) {
    final bool userDriven =
        notification is UserScrollNotification ||
        (notification is ScrollUpdateNotification && notification.dragDetails != null);
    if (userDriven) widget.onInteract();
    // 返回 false：通知继续向上冒泡，不影响其它监听者。
    return false;
  }
}
