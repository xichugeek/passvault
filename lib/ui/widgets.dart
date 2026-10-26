import 'dart:async';

import 'package:flutter/material.dart';

import '../core/password_generator.dart';
import '../core/totp.dart';

/// 条目头像：取标题首字，按标题哈希着色，色板在深浅色下都协调
class EntryAvatar extends StatelessWidget {
  const EntryAvatar({super.key, required this.title, this.size = 42});

  final String title;
  final double size;

  static const _hues = [210.0, 160.0, 280.0, 25.0, 340.0, 190.0, 45.0, 120.0, 250.0, 0.0];

  @override
  Widget build(BuildContext context) {
    final t = title.trim();
    final letter = t.isEmpty ? '?' : String.fromCharCode(t.runes.first).toUpperCase();
    final hue = _hues[t.hashCode.abs() % _hues.length];
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = HSLColor.fromAHSL(1, hue, 0.55, dark ? 0.30 : 0.88).toColor();
    final fg = HSLColor.fromAHSL(1, hue, 0.60, dark ? 0.85 : 0.30).toColor();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Text(
        letter,
        style: TextStyle(
          color: fg,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.42,
        ),
      ),
    );
  }
}

/// 密码强度条
class StrengthBar extends StatelessWidget {
  const StrengthBar({super.key, required this.password, this.showLabel = true});

  final String password;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    if (password.isEmpty) return const SizedBox.shrink();
    final level = PasswordGenerator.strengthLevel(password);
    final colors = [
      Colors.red.shade400,
      Colors.orange.shade400,
      Colors.amber.shade600,
      Colors.lightGreen.shade600,
      Colors.green.shade600,
    ];
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        for (var i = 0; i < 5; i++)
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              height: 5,
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(
                color: i <= level ? colors[level] : scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        if (showLabel) ...[
          const SizedBox(width: 6),
          Text(
            PasswordGenerator.strengthLabels[level],
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: colors[level], fontWeight: FontWeight.w600),
          ),
        ],
      ],
    );
  }
}

/// 实时刷新的 TOTP 验证码 + 倒计时圆环
class TotpView extends StatefulWidget {
  const TotpView({super.key, required this.config, this.onCopy, this.compact = false});

  final TotpConfig config;
  final void Function(String code)? onCopy;
  final bool compact;

  @override
  State<TotpView> createState() => _TotpViewState();
}

class _TotpViewState extends State<TotpView> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final code = widget.config.codeAt(now);
    final remain = widget.config.secondsRemaining(now);
    final scheme = Theme.of(context).colorScheme;
    final pretty = code.length == 6
        ? '${code.substring(0, 3)} ${code.substring(3)}'
        : code.length == 8
            ? '${code.substring(0, 4)} ${code.substring(4)}'
            : code;
    final urgent = remain <= 5;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: widget.onCopy == null ? null : () => widget.onCopy!(code),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              pretty,
              style: (widget.compact
                      ? Theme.of(context).textTheme.titleMedium
                      : Theme.of(context).textTheme.headlineSmall)
                  ?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
                fontWeight: FontWeight.w600,
                letterSpacing: 1.5,
                color: urgent ? scheme.error : scheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 22,
              height: 22,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: remain / widget.config.period,
                    strokeWidth: 3,
                    color: urgent ? scheme.error : scheme.primary,
                    backgroundColor: scheme.surfaceContainerHighest,
                  ),
                  Text('$remain', style: const TextStyle(fontSize: 9)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 分组的卡片容器
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.children, this.title});

  final List<Widget> children;
  final String? title;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
            child: Text(
              title!,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(children: children),
        ),
      ],
    );
  }
}

void showSnack(BuildContext context, String msg, {bool error = false}) {
  final m = ScaffoldMessenger.maybeOf(context);
  if (m == null) return;
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(
    content: Text(msg),
    backgroundColor: error ? Theme.of(context).colorScheme.error : null,
    duration: Duration(seconds: error ? 5 : 2),
  ));
}

Future<bool> confirm(BuildContext context, String title, String message,
    {String ok = '确定', bool destructive = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: Theme.of(c).colorScheme.error,
                  foregroundColor: Theme.of(c).colorScheme.onError,
                  minimumSize: const Size(0, 40),
                )
              : FilledButton.styleFrom(minimumSize: const Size(0, 40)),
          onPressed: () => Navigator.pop(c, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return r ?? false;
}
