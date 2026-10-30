import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../core/clipboard_service.dart';
import '../core/password_generator.dart';
import 'sheet.dart';
import 'widgets.dart';

/// 弹出密码生成器。[forEntry] 为 true 时显示"使用此密码"按钮并返回结果。
Future<String?> showGenerator(BuildContext context, {bool forEntry = false}) {
  return showMenuSheet<String>(context, children: (_) => [GeneratorSheet(forEntry: forEntry)]);
}

class GeneratorSheet extends StatefulWidget {
  const GeneratorSheet({super.key, this.forEntry = false});

  final bool forEntry;

  @override
  State<GeneratorSheet> createState() => _GeneratorSheetState();
}

class _GeneratorSheetState extends State<GeneratorSheet> {
  late GeneratorOptions _o;
  late String _pw;

  @override
  void initState() {
    super.initState();
    _o = context.read<AppState>().settings.generator;
    _pw = PasswordGenerator.generate(_o);
  }

  void _set(GeneratorOptions o) {
    setState(() {
      _o = o;
      _pw = PasswordGenerator.generate(o);
    });
    context.read<AppState>().settings.update((s) => s.generator = o);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final settings = context.read<AppState>().settings;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('生成密码', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SelectableText(
                  _pw,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontFamilyFallback: ['Consolas', 'Roboto Mono', 'Menlo'],
                    fontSize: 20,
                    height: 1.4,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 12),
                StrengthBar(password: _pw),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton.filledTonal(
                tooltip: '换一个',
                onPressed: () => setState(() => _pw = PasswordGenerator.generate(_o)),
                icon: const Icon(Icons.refresh),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: '复制',
                onPressed: () {
                  ClipboardService.copy(_pw,
                      clearAfterSeconds: settings.clipboardClearSeconds);
                  showSnack(context, '已复制');
                },
                icon: const Icon(Icons.copy),
              ),
              const Spacer(),
              Text('长度 ${_o.length}', style: Theme.of(context).textTheme.titleSmall),
            ],
          ),
          Slider(
            value: _o.length.toDouble(),
            min: 8,
            max: 64,
            divisions: 56,
            label: '${_o.length}',
            onChanged: (v) => _set(_o.copyWith(length: v.round())),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilterChip(
                label: const Text('A-Z'),
                selected: _o.upper,
                onSelected: (v) => _set(_o.copyWith(upper: v)),
              ),
              FilterChip(
                label: const Text('a-z'),
                selected: _o.lower,
                onSelected: (v) => _set(_o.copyWith(lower: v)),
              ),
              FilterChip(
                label: const Text('0-9'),
                selected: _o.digits,
                onSelected: (v) => _set(_o.copyWith(digits: v)),
              ),
              FilterChip(
                label: const Text('!@#'),
                selected: _o.symbols,
                onSelected: (v) => _set(_o.copyWith(symbols: v)),
              ),
              FilterChip(
                label: const Text('排除易混淆字符'),
                selected: _o.excludeAmbiguous,
                onSelected: (v) => _set(_o.copyWith(excludeAmbiguous: v)),
              ),
            ],
          ),
          if (widget.forEntry) ...[
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, _pw),
              icon: const Icon(Icons.check),
              label: const Text('使用此密码'),
            ),
          ],
        ],
      ),
    );
  }
}
