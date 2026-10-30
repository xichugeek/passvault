import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// 弹窗内允许用鼠标、触控板拖动（Flutter 在电脑上默认只允许触摸拖动）
class _AnyPointerScroll extends MaterialScrollBehavior {
  const _AnyPointerScroll();

  @override
  Set<PointerDeviceKind> get dragDevices => PointerDeviceKind.values.toSet();
}

/// 拖动条：上下拖动可调整弹窗高度，往下拖到底关闭
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
          height: 30,
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

/// 菜单类弹窗：高度随内容自动适应，内容完整显示（超出屏幕时可滚动），
/// 按住顶部拖动条或弹窗往下拖可关闭。
Future<T?> showMenuSheet<T>(
  BuildContext context, {
  required List<Widget> Function(BuildContext sheetContext) children,
}) {
  final maxH = MediaQuery.sizeOf(context).height * 0.9;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (c) => ScrollConfiguration(
      behavior: const _AnyPointerScroll(),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            bottom: 12 + MediaQuery.viewPaddingOf(c).bottom,
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: children(c)),
        ),
      ),
    ),
  );
}

/// 列表类弹窗（选择分组、新建、图标等）：
/// 初始高度按内容自动计算，尽量完整显示；拖动顶部拖动条可任意调整高度，
/// 往下拖到底关闭；列表内容也可用鼠标直接拖动。
Future<T?> showListSheet<T>(
  BuildContext context, {
  required double contentHeight,
  required Widget Function(BuildContext sheetContext, ScrollController scroll)
  builder,
}) {
  final mq = MediaQuery.of(context);
  final avail = math.max(200.0, mq.size.height - mq.padding.top);
  const maxSize = 0.95;
  final init = ((contentHeight + 30 + mq.viewPadding.bottom) / avail)
      .clamp(0.3, maxSize)
      .toDouble();
  final ctl = DraggableScrollableController();
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    builder: (c) => ScrollConfiguration(
      behavior: const _AnyPointerScroll(),
      child: DraggableScrollableSheet(
        controller: ctl,
        expand: false,
        initialChildSize: init,
        minChildSize: math.min(0.2, init),
        maxChildSize: maxSize,
        // 底部留出系统导航栏的高度，避免最后一项被挡住
        builder: (c, scroll) => SafeArea(
          top: false,
          child: Column(
            children: [
              _DragHandle(
                onDrag: (dy) {
                  if (!ctl.isAttached) return;
                  ctl.jumpTo((ctl.size - dy / avail).clamp(0.12, maxSize));
                },
                onEnd: () {
                  if (ctl.isAttached && ctl.size < 0.2) Navigator.maybePop(c);
                },
              ),
              Expanded(child: builder(c, scroll)),
            ],
          ),
        ),
      ),
    ),
  );
}

/// 页面列表的底部留白：额外留白 + 系统导航栏高度
EdgeInsets pagePadding(
  BuildContext context, {
  double h = 16,
  double top = 8,
  double bottom = 32,
}) => EdgeInsets.fromLTRB(
  h,
  top,
  h,
  bottom + MediaQuery.paddingOf(context).bottom,
);
