import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kdbx/kdbx.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../core/clipboard_service.dart';
import '../core/session.dart';
import '../core/totp.dart';
import '../core/vault.dart';
import 'entry_detail.dart';
import 'entry_edit_page.dart';
import 'generator_sheet.dart';
import 'save_helper.dart';
import 'settings_page.dart';
import 'widgets.dart';

/// 已解锁后的主界面：搜索 + 分组 + 条目列表；宽屏为左右双栏。
class VaultPage extends StatefulWidget {
  const VaultPage({super.key, required this.onSwitchVault});

  final VoidCallback onSwitchVault;

  @override
  State<VaultPage> createState() => _VaultPageState();
}

class _VaultPageState extends State<VaultPage> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  KdbxGroup? _group;
  KdbxEntry? _selected;

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _copy(String label, String value, {bool sensitive = true}) {
    if (value.isEmpty) {
      showSnack(context, '$label为空');
      return;
    }
    final app = context.read<AppState>();
    ClipboardService.copy(value,
        clearAfterSeconds: app.settings.clipboardClearSeconds, sensitive: sensitive);
    showSnack(context, '已复制$label');
  }

  Future<void> _newEntry() async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => EntryEditPage(initialGroup: _group)),
    );
    if (mounted) setState(() {});
  }

  Future<void> _lock() async {
    final app = context.read<AppState>();
    final s = app.session;
    if (s != null && s.isDirty) {
      final ok = await saveSession(context, s);
      if (!ok && mounted) {
        final force = await confirm(context, '有未保存的修改', '锁定后这些修改将丢失，确定锁定吗？',
            ok: '仍然锁定', destructive: true);
        if (!force) return;
      }
    }
    app.lock();
  }

  Future<void> _newGroup(VaultSession s) async {
    final c = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建分组'),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(hintText: '分组名称'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
            onPressed: () => Navigator.pop(ctx, c.text),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty || !mounted) return;
    final g = s.vault.createGroup(name.trim(), parent: _group);
    setState(() => _group = g);
    s.touch();
    await saveSession(context, s);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = app.session!;
    final vault = s.vault;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    if (_group != null && !vault.groups.contains(_group)) _group = null;
    final entries = vault.search(_search.text, inGroup: _group);
    if (_selected != null && !vault.entries.contains(_selected)) _selected = null;

    final list = _EntryList(
      entries: entries,
      selected: wide ? _selected : null,
      onTap: (e) {
        if (wide) {
          setState(() => _selected = e);
        } else {
          Navigator.push(context, MaterialPageRoute(builder: (_) => EntryDetailPage(entry: e)));
        }
      },
      onCopyUser: (e) => _copy('用户名', e.userName, sensitive: false),
      onCopyPassword: (e) => _copy('密码', e.password),
      onCopyTotp: (e) {
        final t = TotpConfig.fromFields(e.allFields);
        if (t != null) _copy('验证码', t.codeAt(DateTime.now()));
      },
      emptyHint: _search.text.isNotEmpty
          ? '没有找到"${_search.text}"'
          : '这里还没有条目，点右下角 + 新建',
    );

    final body = Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: SearchBar(
            controller: _search,
            focusNode: _searchFocus,
            hintText: '搜索 ${entries.length} 个条目',
            leading: const Icon(Icons.search),
            elevation: const WidgetStatePropertyAll(0),
            backgroundColor: WidgetStatePropertyAll(
                Theme.of(context).colorScheme.surfaceContainerHigh),
            trailing: [
              if (_search.text.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => _search.clear()),
                ),
            ],
            onChanged: (_) => setState(() {}),
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: const Text('全部'),
                  selected: _group == null,
                  onSelected: (_) => setState(() => _group = null),
                ),
              ),
              for (final g in vault.groups)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(vault.groupPath(g)),
                    selected: _group == g,
                    onSelected: (_) => setState(() => _group = _group == g ? null : g),
                  ),
                ),
              ActionChip(
                avatar: const Icon(Icons.create_new_folder_outlined, size: 18),
                label: const Text('分组'),
                onPressed: () => _newGroup(s),
              ),
            ],
          ),
        ),
        if (s.offline)
          _Banner(
            icon: Icons.cloud_off,
            text: '无法访问云端文件，正在显示本地缓存（只读）',
            action: TextButton(
              onPressed: () async {
                try {
                  final fresh = await VaultSession.open(s.source, Credentials.fromHash(s.compositeHash));
                  if (fresh.offline) throw Exception('仍无法访问');
                  app.setSession(fresh);
                } catch (e) {
                  if (context.mounted) showSnack(context, '重试失败：$e', error: true);
                }
              },
              child: const Text('重试'),
            ),
          ),
        if (s.lastError != null && !s.saving && s.isDirty)
          _Banner(
            icon: Icons.sync_problem,
            text: '有修改尚未保存到云端',
            action: TextButton(onPressed: () => saveSession(context, s), child: const Text('重新保存')),
          ),
        const SizedBox(height: 4),
        Expanded(child: list),
      ],
    );

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () => _searchFocus.requestFocus(),
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): _newEntry,
        const SingleActivator(LogicalKeyboardKey.keyL, control: true): _lock,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(vault.name),
                Text(
                  s.source.locationHint,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
            actions: [
              _SyncIndicator(session: s),
              IconButton(tooltip: '锁定 (Ctrl+L)', onPressed: _lock, icon: const Icon(Icons.lock_outline)),
              PopupMenuButton<String>(
                onSelected: (v) async {
                  switch (v) {
                    case 'gen':
                      showGenerator(context);
                      break;
                    case 'reload':
                      if (s.isDirty) {
                        final ok = await confirm(context, '重新加载', '本地未保存的修改将丢失，确定吗？', destructive: true);
                        if (!ok) return;
                      }
                      try {
                        await s.reload();
                        if (context.mounted) showSnack(context, '已从云端重新加载');
                      } catch (e) {
                        if (context.mounted) showSnack(context, '加载失败：$e', error: true);
                      }
                      break;
                    case 'settings':
                      if (context.mounted) {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage()));
                      }
                      break;
                    case 'switch':
                      await _lock();
                      widget.onSwitchVault();
                      break;
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'gen', child: ListTile(leading: Icon(Icons.auto_awesome), title: Text('密码生成器'))),
                  PopupMenuItem(value: 'reload', child: ListTile(leading: Icon(Icons.refresh), title: Text('从云端重新加载'))),
                  PopupMenuItem(value: 'settings', child: ListTile(leading: Icon(Icons.settings_outlined), title: Text('设置'))),
                  PopupMenuItem(value: 'switch', child: ListTile(leading: Icon(Icons.swap_horiz), title: Text('切换密码库'))),
                ],
              ),
            ],
          ),
          floatingActionButton: s.offline
              ? null
              : FloatingActionButton.extended(
                  onPressed: _newEntry,
                  icon: const Icon(Icons.add),
                  label: const Text('新建'),
                ),
          body: wide
              ? Row(
                  children: [
                    SizedBox(width: 400, child: body),
                    VerticalDivider(width: 1, color: Theme.of(context).colorScheme.outlineVariant),
                    Expanded(
                      child: _selected == null
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.key_rounded,
                                      size: 64, color: Theme.of(context).colorScheme.outlineVariant),
                                  const SizedBox(height: 12),
                                  Text('选择左侧的条目查看详情',
                                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                                  const SizedBox(height: 4),
                                  Text('Ctrl+F 搜索 · Ctrl+N 新建 · Ctrl+L 锁定',
                                      style: Theme.of(context).textTheme.bodySmall),
                                ],
                              ),
                            )
                          : EntryDetailView(
                              key: ValueKey(_selected!.uuid.uuid),
                              entry: _selected!,
                              embedded: true,
                              onDeleted: () => setState(() => _selected = null),
                            ),
                    ),
                  ],
                )
              : body,
        ),
      ),
    );
  }
}

class _EntryList extends StatelessWidget {
  const _EntryList({
    required this.entries,
    required this.onTap,
    required this.onCopyUser,
    required this.onCopyPassword,
    required this.onCopyTotp,
    required this.emptyHint,
    this.selected,
  });

  final List<KdbxEntry> entries;
  final KdbxEntry? selected;
  final void Function(KdbxEntry) onTap;
  final void Function(KdbxEntry) onCopyUser;
  final void Function(KdbxEntry) onCopyPassword;
  final void Function(KdbxEntry) onCopyTotp;
  final String emptyHint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(emptyHint, textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant)),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 96),
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final e = entries[i];
        final hasTotp = TotpConfig.fromFields(e.allFields) != null;
        final subtitle = e.userName.isNotEmpty ? e.userName : _host(e.url);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: ListTile(
            selected: selected == e,
            selectedTileColor: scheme.secondaryContainer,
            leading: EntryAvatar(title: e.title),
            title: Text(e.title.isEmpty ? '（无标题）' : e.title,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w500)),
            subtitle: subtitle.isEmpty
                ? null
                : Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () => onTap(e),
            onLongPress: () => _menu(context, e, hasTotp),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasTotp)
                  IconButton(
                    tooltip: '复制验证码',
                    icon: const Icon(Icons.timer_outlined, size: 20),
                    onPressed: () => onCopyTotp(e),
                  ),
                IconButton(
                  tooltip: '复制密码',
                  icon: const Icon(Icons.copy_rounded, size: 20),
                  onPressed: () => onCopyPassword(e),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _menu(BuildContext context, KdbxEntry e, bool hasTotp) {
    showModalBottomSheet(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('复制用户名'),
              onTap: () {
                Navigator.pop(c);
                onCopyUser(e);
              },
            ),
            ListTile(
              leading: const Icon(Icons.password_rounded),
              title: const Text('复制密码'),
              onTap: () {
                Navigator.pop(c);
                onCopyPassword(e);
              },
            ),
            if (hasTotp)
              ListTile(
                leading: const Icon(Icons.timer_outlined),
                title: const Text('复制验证码'),
                onTap: () {
                  Navigator.pop(c);
                  onCopyTotp(e);
                },
              ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('编辑'),
              onTap: () {
                Navigator.pop(c);
                Navigator.push(context, MaterialPageRoute(builder: (_) => EntryEditPage(entry: e)));
              },
            ),
          ],
        ),
      ),
    );
  }

  static String _host(String url) {
    if (url.isEmpty) return '';
    final u = Uri.tryParse(url.contains('://') ? url : 'https://$url');
    return u?.host ?? url;
  }
}

class _SyncIndicator extends StatelessWidget {
  const _SyncIndicator({required this.session});

  final VaultSession session;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (session.saving) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (session.offline) {
      return Tooltip(message: '离线只读', child: Icon(Icons.cloud_off, color: scheme.error));
    }
    if (session.isDirty) {
      return IconButton(
        tooltip: '有未保存修改，点击保存',
        icon: Icon(Icons.cloud_upload_outlined, color: scheme.tertiary),
        onPressed: () => saveSession(context, session),
      );
    }
    return Tooltip(
      message: session.lastSaved == null ? '已同步' : '已保存',
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(Icons.cloud_done_outlined, color: scheme.primary),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: scheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(color: scheme.onErrorContainer))),
          ?action,
        ],
      ),
    );
  }
}
