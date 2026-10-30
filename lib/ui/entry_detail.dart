import 'package:flutter/material.dart';
import 'package:kdbx/kdbx.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../core/clipboard_service.dart';
import '../core/templates.dart';
import '../core/totp.dart';
import '../core/vault.dart';
import 'entry_edit_page.dart';
import 'group_actions.dart';
import 'kp_icons.dart';
import 'save_helper.dart';
import 'widgets.dart';
import 'sheet.dart';

/// 条目详情内容（宽屏右侧面板与窄屏独立页面共用）
class EntryDetailView extends StatefulWidget {
  const EntryDetailView({super.key, required this.entry, this.onDeleted, this.embedded = false});

  final KdbxEntry entry;
  final VoidCallback? onDeleted;
  final bool embedded;

  @override
  State<EntryDetailView> createState() => EntryDetailViewState();
}

class EntryDetailViewState extends State<EntryDetailView> {
  final Set<String> _revealed = {};

  static bool _isOtpField(String k) =>
      k == Fields.otp || k.startsWith('TimeOtp-') || k == 'TOTP Seed' || k == 'TOTP Settings';

  void _copy(String label, String value, {bool sensitive = true}) {
    final app = context.read<AppState>();
    ClipboardService.copy(value, clearAfterSeconds: app.settings.clipboardClearSeconds, sensitive: sensitive);
    final secs = app.settings.clipboardClearSeconds;
    showSnack(context, sensitive && secs > 0 ? '已复制$label，$secs 秒后清除' : '已复制$label');
  }

  Future<void> edit() async {
    final r = await Navigator.push<KdbxEntry>(
      context,
      MaterialPageRoute(builder: (_) => EntryEditPage(entry: widget.entry)),
    );
    if (r != null && mounted) setState(() {});
  }

  Future<void> move() async {
    final s = context.read<AppState>().session!;
    await moveEntryTo(context, s, widget.entry);
    if (mounted) setState(() {});
  }

  Future<void> delete() async {
    final s = context.read<AppState>().session!;
    if (await deleteEntry(context, s, widget.entry)) widget.onDeleted?.call();
  }

  Future<void> restore() async {
    final s = context.read<AppState>().session!;
    s.vault.restore(widget.entry);
    s.touch();
    await saveSession(context, s);
    if (mounted) showSnack(context, '已恢复到"${s.vault.groupName(widget.entry.parent!)}"');
  }

  void _toggle(String key) =>
      setState(() => _revealed.contains(key) ? _revealed.remove(key) : _revealed.add(key));

  void _openUrl(String raw) {
    var u = raw.trim();
    if (!u.contains('://')) u = 'https://$u';
    final uri = Uri.tryParse(u);
    if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// 单个字段的显示行；值为空时返回 null
  Widget? _row(KdbxEntry e, String key, String label, {TFieldType type = TFieldType.inline}) {
    final scheme = Theme.of(context).colorScheme;
    if (key == '@exp_date') {
      final d = e.expiry;
      if (d == null) return null;
      final expired = e.isExpired;
      return ListTile(
        leading: Icon(Icons.event_available_outlined, color: expired ? scheme.error : null),
        title: Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
        subtitle: Text('${fmtDate(d)}${expired ? '（已过期）' : ''}',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: expired ? scheme.error : scheme.onSurface)),
      );
    }
    if (key == '@tags') {
      final t = e.tags.get() ?? '';
      if (t.trim().isEmpty) return null;
      return _FieldTile(icon: Icons.sell_outlined, label: label, value: t);
    }
    if (key.startsWith('@')) return null;
    final value = e.str(key);
    if (type == TFieldType.checkbox) {
      return _FieldTile(
        icon: Icons.check_box_outlined,
        label: label,
        value: value.toLowerCase() == 'true' ? '是' : '否',
      );
    }
    if (value.isEmpty) return null;
    if (key == Fields.password) {
      return _FieldTile(
        icon: Icons.password_rounded,
        label: label,
        value: value,
        obscured: !_revealed.contains(key),
        monospace: true,
        onToggle: () => _toggle(key),
        onCopy: () => _copy(label, value),
        footer: Padding(
          padding: const EdgeInsets.only(top: 6, right: 48),
          child: StrengthBar(password: value),
        ),
      );
    }
    final protected = e.isProtected(key) || type.isProtected;
    if (protected) {
      return _FieldTile(
        icon: Icons.lock_outline,
        label: label,
        value: value,
        obscured: !_revealed.contains(key),
        monospace: true,
        onToggle: () => _toggle(key),
        onCopy: () => _copy(label, value),
      );
    }
    if (key == Fields.url || type == TFieldType.inlineUrl) {
      return _FieldTile(
        icon: Icons.link_rounded,
        label: label,
        value: value,
        onCopy: () => _copy(label, value, sensitive: false),
        extra: IconButton(
          tooltip: '打开',
          icon: const Icon(Icons.open_in_new_rounded),
          onPressed: () => _openUrl(value),
        ),
      );
    }
    final icon = switch (key) {
      Fields.userName => Icons.person_outline,
      Fields.notes => Icons.notes,
      _ => type.isDate ? Icons.event_outlined : Icons.label_outline,
    };
    return _FieldTile(
      icon: icon,
      label: label,
      value: value,
      onCopy: () => _copy(label, value, sensitive: false),
    );
  }

  Widget _totpTile(TotpConfig totp) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: const Icon(Icons.timer_outlined),
      title: Text('动态验证码', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
      subtitle: Align(
        alignment: Alignment.centerLeft,
        child: TotpView(config: totp, onCopy: (c) => _copy('验证码', c)),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.copy_rounded),
        onPressed: () => _copy('验证码', totp.codeAt(DateTime.now())),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    context.watch<AppState>(); // 保存/修改后刷新
    final e = widget.entry;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final session = context.read<AppState>().session;
    if (session == null) return const SizedBox.shrink();
    final vault = session.vault;
    final totp = TotpConfig.fromFields(e.allFields);
    final tpl = Templates(vault).templateOf(e);
    final inBin = vault.inRecycleBin(e);
    final groupPath = e.parent == null ? '' : (e.parent == vault.root ? vault.name : vault.groupPath(e.parent!));

    final sections = <Widget>[];
    void addSection(String? title, List<Widget?> rows) {
      final r = rows.whereType<Widget>().toList();
      if (r.isEmpty) return;
      sections.add(Padding(
        padding: const EdgeInsets.only(top: 16),
        child: SectionCard(title: title, children: r),
      ));
    }

    final shownKeys = <String>{Fields.title};
    if (tpl != null) {
      // 按模板定义的顺序与分节显示
      String? sectionTitle;
      var rows = <Widget?>[];
      for (final f in tpl.fields) {
        shownKeys.add(f.key);
        if (f.type == TFieldType.divider) {
          addSection(sectionTitle, rows);
          sectionTitle = f.displayLabel;
          rows = [];
          continue;
        }
        if (f.key == Fields.title) continue;
        if (f.key == Fields.notes) continue; // 备注单独显示
        rows.add(_row(e, f.key, f.displayLabel, type: f.type));
      }
      // 模板没有、但条目里有内容的标准字段
      for (final k in [Fields.userName, Fields.password, Fields.url]) {
        if (shownKeys.add(k)) rows.add(_row(e, k, TField(k, TFieldType.inline).displayLabel));
      }
      if (totp != null) rows.add(_totpTile(totp));
      if (!shownKeys.contains('@exp_date')) rows.add(_row(e, '@exp_date', '有效期至'));
      addSection(sectionTitle, rows);
    } else {
      addSection(null, [
        _row(e, Fields.userName, '用户名'),
        e.password.isEmpty
            ? const _FieldTile(icon: Icons.password_rounded, label: '密码', value: '')
            : _row(e, Fields.password, '密码'),
        if (totp != null) _totpTile(totp),
        _row(e, Fields.url, '网址'),
        _row(e, '@exp_date', '有效期至'),
      ]);
      shownKeys.addAll([Fields.userName, Fields.password, Fields.url]);
    }

    final extras = <Widget?>[
      for (final kv in e.visibleCustomFields.entries)
        if (!_isOtpField(kv.key) && !shownKeys.contains(kv.key)) _row(e, kv.key, kv.key),
    ];
    addSection('其他字段', extras);

    if (e.notes.isNotEmpty) {
      sections.add(Padding(
        padding: const EdgeInsets.only(top: 16),
        child: SectionCard(title: '备注', children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: SelectableText(e.notes)),
                IconButton(
                  icon: const Icon(Icons.copy_rounded),
                  onPressed: () => _copy('备注', e.notes, sensitive: false),
                ),
              ],
            ),
          ),
        ]),
      ));
    }

    if (e.binaryEntries.isNotEmpty) {
      sections.add(Padding(
        padding: const EdgeInsets.only(top: 16),
        child: SectionCard(title: '附件', children: [
          for (final b in e.binaryEntries)
            ListTile(
              leading: const Icon(Icons.attach_file),
              title: Text(b.key.key),
              subtitle: Text('${(b.value.value.length / 1024).toStringAsFixed(1)} KB'),
            ),
        ]),
      ));
    }

    return ListView(
      padding: pagePadding(context),
      children: [
        if (inBin)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
            decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: [
                Icon(Icons.delete_outline, size: 18, color: scheme.onErrorContainer),
                const SizedBox(width: 8),
                Expanded(child: Text('此条目在回收站中', style: TextStyle(color: scheme.onErrorContainer))),
                TextButton(onPressed: restore, child: const Text('恢复')),
              ],
            ),
          ),
        Row(
          children: [
            KpIcon.of(e, size: 56),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.title.isEmpty ? '（无标题）' : e.title,
                      style: text.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Wrap(
                    spacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (groupPath.isNotEmpty) ...[
                        Icon(Icons.folder_outlined, size: 14, color: scheme.onSurfaceVariant),
                        Text(groupPath, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                      ],
                      if (tpl != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: scheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(tpl.title,
                              style: text.labelSmall?.copyWith(color: scheme.onSecondaryContainer)),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (widget.embedded) ...[
              IconButton(tooltip: '编辑', onPressed: edit, icon: const Icon(Icons.edit_outlined)),
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'move') move();
                  if (v == 'delete') delete();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'move', child: ListTile(leading: Icon(Icons.drive_file_move_outline), title: Text('移动到…'))),
                  PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline), title: Text('删除'))),
                ],
              ),
            ],
          ],
        ),
        ...sections,
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

  String _fmt(DateTime d) => '${d.year}-${_pad(d.month)}-${_pad(d.day)} ${_pad(d.hour)}:${_pad(d.minute)}';
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
  final detailKey = GlobalKey<EntryDetailViewState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: '编辑',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => detailKey.currentState?.edit(),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'move') detailKey.currentState?.move();
              if (v == 'delete') detailKey.currentState?.delete();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'move', child: ListTile(leading: Icon(Icons.drive_file_move_outline), title: Text('移动到…'))),
              PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline), title: Text('删除'))),
            ],
          ),
        ],
      ),
      body: EntryDetailView(
        key: detailKey,
        entry: widget.entry,
        onDeleted: () => Navigator.pop(context),
      ),
    );
  }
}
