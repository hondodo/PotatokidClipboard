import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 跨格 + 「空白处长按」进入编辑态的拖拽网格（手机桌面式交互）。
///
/// 交互约定（避免滚动/卡片操作被排序抢走）：
///  1. 卡片上**没有**任何长按识别器：滚动、点按钮、拖亮度条都按原样工作；
///  2. 在网格的空白处（卡片间隙、下方空白区）长按 500ms → 进入编辑态；
///  3. 编辑态：卡片抖动浮起，直接拖动卡片到另一张上松手 → 交换位置；
///  4. 点右上角「完成」退出编辑态。
///
/// 跨格实现：用原生 Wrap + 固定格宽计算，卡片按 col×row 占不同宽高。
/// 零第三方依赖，Wrap 自算高度，放进 SingleChildScrollView 完全正常
/// （不像 flutter_staggered_grid_view 0.6/0.7 的 StaggeredGrid 不可滚动）。
class SpanReorderableGrid<T> extends StatefulWidget {
  const SpanReorderableGrid({
    super.key,
    required this.items,
    required this.spanOf,
    required this.keyOf,
    required this.itemBuilder,
    required this.onReorder,
    this.crossAxisCount = 4,
    this.mainAxisSpacing = 14,
    this.crossAxisSpacing = 14,
    this.cellExtent = 188,
    this.padding = const EdgeInsets.all(16),
    this.scrollController,
  });

  final List<T> items;
  final CardGridSpan Function(T item) spanOf;
  final String Function(T item) keyOf;
  final Widget Function(BuildContext context, int index, T item) itemBuilder;
  final ValueChanged<List<int>> onReorder;
  final int crossAxisCount;
  final double mainAxisSpacing;
  final double crossAxisSpacing;

  /// row=1 的基准高度（像素）。
  final double cellExtent;
  final EdgeInsets padding;
  final ScrollController? scrollController;

  @override
  State<SpanReorderableGrid<T>> createState() => _SpanReorderableGridState<T>();
}

/// 卡片跨格尺寸（与 domain 的 CardSpan 解耦）。
class CardGridSpan {
  const CardGridSpan({this.col = 1, this.row = 1});
  final int col;
  final int row;
}

class _SpanReorderableGridState<T> extends State<SpanReorderableGrid<T>> {
  bool _editing = false;
  int? _draggingIndex;
  int? _hoverIndex;

  void _enterEditing() {
    if (!_editing && mounted) setState(() => _editing = true);
  }

  void _exitEditing() {
    if (mounted) {
      setState(() {
        _editing = false;
        _draggingIndex = null;
        _hoverIndex = null;
      });
    }
  }

  void _swap(int from, int to) {
    if (from == to || from < 0 || to < 0) return;
    if (from >= widget.items.length || to >= widget.items.length) return;
    final List<int> order = List<int>.generate(widget.items.length, (int i) => i);
    final int tmp = order[from];
    order[from] = order[to];
    order[to] = tmp;
    widget.onReorder(order);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double usableWidth = constraints.maxWidth -
            widget.padding.horizontal -
            widget.crossAxisSpacing * (widget.crossAxisCount - 1);
        final double cellWidth = usableWidth / widget.crossAxisCount;

        // 让「空白区」覆盖整个可视区域：内容比视口短时，下方剩余空间也能长按。
        final double minContentHeight = constraints.maxHeight.isFinite
            ? math.max(0.0, constraints.maxHeight - widget.padding.vertical)
            : 0.0;

        final List<Widget> cells = <Widget>[];
        for (int i = 0; i < widget.items.length; i++) {
          final T item = widget.items[i];
          final CardGridSpan span = widget.spanOf(item);
          final int col = span.col.clamp(1, widget.crossAxisCount);
          final int row = span.row.clamp(1, 4);
          final double width = cellWidth * col + widget.crossAxisSpacing * (col - 1);
          final double height = widget.cellExtent * row + widget.mainAxisSpacing * (row - 1);

          cells.add(
            SizedBox(
              width: width,
              height: height,
              child: _buildCell(context, i, item, width, height),
            ),
          );
        }

        return Stack(
          children: <Widget>[
            SingleChildScrollView(
              controller: widget.scrollController,
              // 空白处的长按手势：与 ScrollView 的纵向拖拽竞争手势竞技场，
              // 按住不动 500ms 才进入编辑态；一旦开始滚动就由 ScrollView 接管。
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onLongPress: _enterEditing,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: minContentHeight),
                  child: Padding(
                    padding: widget.padding,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Wrap(
                          spacing: widget.crossAxisSpacing,
                          runSpacing: widget.mainAxisSpacing,
                          children: cells,
                        ),
                        SizedBox(
                          height: 52,
                          child: Center(
                            child: Text(
                              _editing ? '拖动卡片交换位置 · 点右上角完成' : '长按空白处排列卡片',
                              style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: _editing ? 0.5 : 0.28),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (_editing)
              Positioned(
                top: 8,
                right: 16,
                child: SafeArea(
                  child: ElevatedButton.icon(
                    onPressed: _exitEditing,
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('完成'),
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildCell(BuildContext context, int index, T item, double width, double height) {
    final Widget base = widget.itemBuilder(context, index, item);
    final bool isDragging = _draggingIndex == index;
    final bool isHover = _hoverIndex == index && _draggingIndex != null && _draggingIndex != index;

    Widget cell = base;
    if (_editing && !isDragging) {
      cell = _Jiggle(seed: index, child: cell);
    }
    if (isDragging) {
      cell = Opacity(opacity: 0.35, child: cell);
    }
    cell = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: isHover
            ? <BoxShadow>[
                BoxShadow(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
                  blurRadius: 12,
                ),
              ]
            : null,
      ),
      child: cell,
    );

    // 卡片自身吞掉长按事件：既不进入编辑态，也不让外层「空白处长按」触发。
    // 卡片上的按钮、亮度条等子手势不受影响。
    cell = GestureDetector(
      onLongPress: () {},
      child: cell,
    );

    // 只有编辑态才允许拖动卡片，滚动手势永远不会和排序抢竞技场。
    if (_editing) {
      cell = Draggable<int>(
        data: index,
        onDragStarted: () {
          if (mounted) setState(() => _draggingIndex = index);
        },
        onDragEnd: (DraggableDetails details) => _clearDrag(),
        onDraggableCanceled: (_, _) => _clearDrag(),
        feedback: Material(
          color: Colors.transparent,
          child: SizedBox(
            width: math.min(width, 320),
            height: math.min(height, 340),
            child: Transform.scale(
              scale: 1.05,
              child: Card(
                elevation: 12,
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                child: base,
              ),
            ),
          ),
        ),
        childWhenDragging: const SizedBox.shrink(),
        child: cell,
      );
    }

    return DropTarget(
      index: index,
      enabled: _editing,
      onHover: (bool hovering) {
        if (mounted) {
          setState(() {
            _hoverIndex = hovering ? index : (_hoverIndex == index ? null : _hoverIndex);
          });
        }
      },
      onDrop: (int fromIndex) => _swap(fromIndex, index),
      child: cell,
    );
  }

  void _clearDrag() {
    if (mounted && (_draggingIndex != null || _hoverIndex != null)) {
      setState(() {
        _draggingIndex = null;
        _hoverIndex = null;
      });
    }
  }
}

/// DragTarget 包装：进入时高亮，松手时把拖动源 index 交给 onDrop。
class DropTarget extends StatelessWidget {
  const DropTarget({
    super.key,
    required this.index,
    required this.enabled,
    required this.onHover,
    required this.onDrop,
    required this.child,
  });

  final int index;
  final bool enabled;
  final ValueChanged<bool> onHover;
  final ValueChanged<int> onDrop;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return DragTarget<int>(
      onWillAcceptWithDetails: (DragTargetDetails<int> details) => details.data != index,
      onAcceptWithDetails: (DragTargetDetails<int> details) => onDrop(details.data),
      onMove: (_) => onHover(true),
      onLeave: (_) => onHover(false),
      builder: (BuildContext context, List<int?> candidate, List<dynamic> rejected) => child,
    );
  }
}

/// 编辑态轻微抖动动画：±1.2° 旋转 + 微缩，循环。
class _Jiggle extends StatefulWidget {
  const _Jiggle({required this.seed, required this.child});
  final int seed;
  final Widget child;

  @override
  State<_Jiggle> createState() => _JiggleState();
}

class _JiggleState extends State<_Jiggle> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 197),
  )..repeat(reverse: true);
  late final double _phase = (widget.seed % 5) * 0.4;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) {
        final double wave = math.sin((_controller.value + _phase) * math.pi * 2);
        return Transform.rotate(
          angle: wave * 0.021,
          child: Transform.scale(scale: 1 + wave * 0.012, child: child),
        );
      },
      child: widget.child,
    );
  }
}
