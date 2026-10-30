import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// 弹窗内允许用鼠标、触控板拖动（Flutter 在电脑上默认只允许触摸拖动）
class _AnyPointerScroll extends MaterialScrollBehavior {
  const _AnyPointerScroll();

  @override
  Set<PointerDeviceKind> get dragDevices => PointerDeviceKind.values.toSet();
}

const _maxSize = 0.95;
const _minSize = 0.08;
const _handleHeight = 30.0;

/// 拖动条：上下拖动调整弹窗高度，往下拖到底关闭
class _DragHandle extends StatelessWidget {
  const _DragHandle({required this.onDrag, required this.onEnd});

  final void Function(double dy) onDrag;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeUpDown,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: (d) => onDrag(d.delta.dy),
        onVerticalDragEnd: (_) => onEnd(),
        child: SizedBox(
          height: _handleHeight,
          width: double.infinity,
          child: Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 统一的可拖动弹窗外壳
class _SheetFrame extends StatefulWidget {
  const _SheetFrame({
    required this.initial,
    required this.avail,
    required this.fitToContent,
    required this.builder,
  });

  final double initial;
  final double avail;

  /// 打开后测量内容实际高度，让弹窗刚好完整显示
  final bool fitToContent;
  final Widget Function(BuildContext context, ScrollController scroll, GlobalKey contentKey) builder;

  @override
  State<_SheetFrame> createState() => _SheetFrameState();
}

class _SheetFrameState extends State<_SheetFrame> {
  final _ctl = DraggableScrollableController();
  final _contentKey = GlobalKey();
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    if (widget.fitToContent) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fit());
    }
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _fit() {
    if (!mounted || !_ctl.isAttached) return;
    final box = _contentKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    final h = box.size.height + _handleHeight + 12 + bottom;
    _ctl.jumpTo((h / widget.avail).clamp(_minSize + 0.05, _maxSize).toDouble());
  }

  void _close() {
    if (_closing) return;
    _closing = true;
    Navigator.maybePop(context);
  }

  @override
  Widget build(BuildContext context) {
    return ScrollConfiguration(
      behavior: const _AnyPointerScroll(),
      child: NotificationListener<DraggableScrollableNotification>(
        onNotification: (n) {
          // 拖到最底部即关闭
          if (n.extent <= _minSize + 0.01) _close();
          return false;
        },
        child: DraggableScrollableSheet(
          controller: _ctl,
          expand: false,
          initialChildSize: widget.initial,
          minChildSize: _minSize,
          maxChildSize: _maxSize,
          builder: (c, scroll) => SafeArea(
            top: false,
            child: Column(
              children: [
                _DragHandle(
                  onDrag: (dy) {
                    if (!_ctl.isAttached) return;
                    _ctl.jumpTo((_ctl.size - dy / widget.avail).clamp(_minSize, _maxSize).toDouble());
                  },
                  onEnd: () {
                    if (_ctl.isAttached && _ctl.size < 0.18) _close();
                  },
                ),
                Expanded(child: widget.builder(c, scroll, _contentKey)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<T?> _show<T>(
  BuildContext context, {
  required double estimatedHeight,
  required bool fitToContent,
  required Widget Function(BuildContext, ScrollController, GlobalKey) builder,
}) {
  final mq = MediaQuery.of(context);
  final avail = math.max(200.0, mq.size.height - mq.padding.top);
  final init = ((estimatedHeight + _handleHeight + 12 + mq.viewPadding.bottom) / avail)
      .clamp(0.25, _maxSize)
      .toDouble();
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    // 拖动由弹窗自己处理（可上下拖、拖到底关闭）
    enableDrag: false,
    builder: (c) => _SheetFrame(
      initial: init,
      avail: avail,
      fitToContent: fitToContent,
      builder: builder,
    ),
  );
}

/// 菜单类弹窗：打开时自动量好高度，刚好完整显示；
/// 按住顶部拖动条或弹窗内容可上下拖动，拖到底关闭。
Future<T?> showMenuSheet<T>(
  BuildContext context, {
  required List<Widget> Function(BuildContext sheetContext) children,
}) {
  return _show<T>(
    context,
    estimatedHeight: 420,
    fitToContent: true,
    builder: (c, scroll, key) => SingleChildScrollView(
      controller: scroll,
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(key: key, mainAxisSize: MainAxisSize.min, children: children(c)),
    ),
  );
}

/// 列表类弹窗（选择分组、新建、图标等）：初始高度按内容估算，尽量完整显示；
/// 按住顶部拖动条或列表可上下拖动，拖到底关闭。
Future<T?> showListSheet<T>(
  BuildContext context, {
  required double contentHeight,
  required Widget Function(BuildContext sheetContext, ScrollController scroll) builder,
}) {
  return _show<T>(
    context,
    estimatedHeight: contentHeight,
    fitToContent: false,
    builder: (c, scroll, _) => builder(c, scroll),
  );
}

/// 页面列表的底部留白：额外留白 + 系统导航栏高度
EdgeInsets pagePadding(BuildContext context, {double h = 16, double top = 8, double bottom = 32}) =>
    EdgeInsets.fromLTRB(h, top, h, bottom + MediaQuery.paddingOf(context).bottom);
