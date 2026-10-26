import 'package:flutter/material.dart';
import 'package:kdbx/kdbx.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../core/clipboard_service.dart';
import '../core/totp.dart';
import '../core/vault.dart';
import 'entry_edit_page.dart';
import 'save_helper.dart';
import 'widgets.dart';

/// 条目详情内容（宽屏右侧面板与窄屏独立页面共用）
class EntryDetailView extends StatefulWidget {
  const EntryDetailView({super.key, required this.entry, this.onDeleted, this.embedded = false});

  final KdbxEntry entry;
  final VoidCallback? onDeleted;
  final bool embedded;

  @override
  State<EntryDetailView> createState() => _EntryDetailViewState();
}

class _EntryDetailViewState extends State<EntryDetailView> {
  final Set<String> _revealed = {};

  void _copy(String label, String value, {bool sensitive = true}) {
    final app = context.read<AppState>();
    ClipboardService.copy(value,
        clearAfterSeconds: app.settings.clipboardClearSeconds, sensitive: sensitive);
    final secs = app.settings.clipboardClearSeconds;
    showSnack(context, sensitive && secs > 0 ? '已复制$label，$secs 秒后清除' : '已复制$label');
  }

  Future<void> _edit() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => EntryEditPage(entry: widget.entry)),
    );
    if (changed == true && mounted) setState(() {});
  }

  Future<void> _delete() async {
    final app = context.read<AppState>();
    final s = app.session!;
    final ok = await confirm(context, '删除条目', '将"${widget.entry.title}"移入回收站？',
        ok: '删除', destructive: true);
    if (!ok || !mounted) return;
    s.vault.deleteEntry(widget.entry);
    s.touch();
    widget.onDeleted?.call();
    await saveSession(context, s);
  }

  @override
  Widget build(BuildContext context) {
    context.watch<AppState>(); // 保存/修改后刷新
    final e = widget.entry;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final totp = TotpConfig.fromFields(e.allFields);
    final custom = Map.of(e.customFields)
      ..removeWhere((k, _) =>
          k == Fields.otp ||
          k.startsWith('TimeOtp-') ||
          k == 'TOTP Seed' ||
          k == 'TOTP Settings');
    final session = context.read<AppState>().session;
    final groupPath = e.parent == null || session == null ? '' : session.vault.groupPath(e.parent!);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Row(
          children: [
            EntryAvatar(title: e.title, size: 56),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.title.isEmpty ? '（无标题）' : e.title,
                      style: text.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
                  if (groupPath.isNotEmpty)
                    Text(groupPath, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            if (widget.embedded) ...[
              IconButton(tooltip: '编辑', onPressed: _edit, icon: const Icon(Icons.edit_outlined)),
              IconButton(tooltip: '删除', onPressed: _delete, icon: const Icon(Icons.delete_outline)),
            ],
          ],
        ),
        const SizedBox(height: 20),
        SectionCard(children: [
          if (e.userName.isNotEmpty)
            _FieldTile(
              icon: Icons.person_outline,
              label: '用户名',
              value: e.userName,
              onCopy: () => _copy('用户名', e.userName, sensitive: false),
            ),
          _FieldTile(
            icon: Icons.password_rounded,
            label: '密码',
            value: e.password,
            obscured: !_revealed.contains(Fields.password),
            monospace: true,
            onToggle: () => setState(() => _revealed.contains(Fields.password)
                ? _revealed.remove(Fields.password)
                : _revealed.add(Fields.password)),
            onCopy: e.password.isEmpty ? null : () => _copy('密码', e.password),
            footer: e.password.isEmpty
                ? null
                : Padding(
                    padding: const EdgeInsets.only(top: 6, right: 48),
                    child: StrengthBar(password: e.password),
                  ),
          ),
          if (totp != null)
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: Text('动态验证码', style: text.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
              subtitle: Align(
                alignment: Alignment.centerLeft,
                child: TotpView(config: totp, onCopy: (c) => _copy('验证码', c)),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.copy_rounded),
                onPressed: () => _copy('验证码', totp.codeAt(DateTime.now())),
              ),
            ),
          if (e.url.isNotEmpty)
            _FieldTile(
              icon: Icons.link_rounded,
              label: '网址',
              value: e.url,
              onCopy: () => _copy('网址', e.url, sensitive: false),
              extra: IconButton(
                tooltip: '打开',
                icon: const Icon(Icons.open_in_new_rounded),
                onPressed: () {
                  var u = e.url.trim();
                  if (!u.contains('://')) u = 'https://$u';
                  final uri = Uri.tryParse(u);
                  if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication);
                },
              ),
            ),
        ]),
        if (custom.isNotEmpty) ...[
          const SizedBox(height: 16),
          SectionCard(title: '其他字段', children: [
            for (final kv in custom.entries)
              _FieldTile(
                icon: Icons.label_outline,
                label: kv.key,
                value: kv.value,
                obscured: e.isProtected(kv.key) && !_revealed.contains(kv.key),
                onToggle: e.isProtected(kv.key)
                    ? () => setState(() => _revealed.contains(kv.key)
                        ? _revealed.remove(kv.key)
                        : _revealed.add(kv.key))
                    : null,
                onCopy: () => _copy(kv.key, kv.value, sensitive: e.isProtected(kv.key)),
              ),
          ]),
        ],
        if (e.notes.isNotEmpty) ...[
          const SizedBox(height: 16),
          SectionCard(title: '备注', children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(width: double.infinity, child: SelectableText(e.notes)),
            ),
          ]),
        ],
        if (e.binaryEntries.isNotEmpty) ...[
          const SizedBox(height: 16),
          SectionCard(title: '附件', children: [
            for (final b in e.binaryEntries)
              ListTile(
                leading: const Icon(Icons.attach_file),
                title: Text(b.key.key),
                subtitle: Text('${(b.value.value.length / 1024).toStringAsFixed(1)} KB'),
              ),
          ]),
        ],
        const SizedBox(height: 16),
        if (e.modified != null)
          Center(
            child: Text(
              '最后修改：${_fmt(e.modified!)}',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
      ],
    );
  }

  String _fmt(DateTime d) =>
      '${d.year}-${_pad(d.month)}-${_pad(d.day)} ${_pad(d.hour)}:${_pad(d.minute)}';
  String _pad(int n) => n.toString().padLeft(2, '0');
}

class _FieldTile extends StatelessWidget {
  const _FieldTile({
    required this.icon,
    required this.label,
    required this.value,
    this.obscured = false,
    this.monospace = false,
    this.onToggle,
    this.onCopy,
    this.extra,
    this.footer,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool obscured;
  final bool monospace;
  final VoidCallback? onToggle;
  final VoidCallback? onCopy;
  final Widget? extra;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final shown = obscured ? '•' * (value.isEmpty ? 0 : 12) : value;
    return ListTile(
      leading: Icon(icon),
      onTap: onCopy,
      title: Text(label, style: text.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value.isEmpty ? '（空）' : shown,
            style: text.bodyLarge?.copyWith(
              fontFamily: monospace && !obscured ? 'monospace' : null,
              fontFamilyFallback: const ['Consolas', 'Roboto Mono'],
              color: scheme.onSurface,
            ),
          ),
          ?footer,
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onToggle != null)
            IconButton(
              icon: Icon(obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined),
              onPressed: onToggle,
            ),
          ?extra,
          if (onCopy != null)
            IconButton(icon: const Icon(Icons.copy_rounded), onPressed: onCopy),
        ],
      ),
    );
  }
}

/// 窄屏下的独立详情页
class EntryDetailPage extends StatefulWidget {
  const EntryDetailPage({super.key, required this.entry});

  final KdbxEntry entry;

  @override
  State<EntryDetailPage> createState() => _EntryDetailPageState();
}

class _EntryDetailPageState extends State<EntryDetailPage> {
  final detailKey = GlobalKey<_EntryDetailViewState>();

  KdbxEntry get entry => widget.entry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: '编辑',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => detailKey.currentState?._edit(),
          ),
          IconButton(
            tooltip: '删除',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => detailKey.currentState?._delete(),
          ),
        ],
      ),
      body: EntryDetailView(
        key: detailKey,
        entry: entry,
        onDeleted: () => Navigator.pop(context),
      ),
    );
  }
}
