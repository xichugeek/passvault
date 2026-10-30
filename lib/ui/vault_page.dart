import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kdbx/kdbx.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../core/clipboard_service.dart';
import '../core/session.dart';
import '../core/templates.dart';
import '../core/totp.dart';
import '../core/vault.dart';
import 'entry_detail.dart';
import 'entry_edit_page.dart';
import 'generator_sheet.dart';
import 'group_actions.dart';
import 'kp_icons.dart';
import 'recycle_bin_page.dart';
import 'save_helper.dart';
import 'settings_page.dart';
import 'widgets.dart';

/// 已解锁后的主界面。
/// - 窄屏（手机）：像文件夹一样逐级进入分组
/// - 中屏：左侧分组树 + 条目列表
/// - 宽屏（电脑）：左侧分组树 + 条目列表 + 右侧详情
class VaultPage extends StatefulWidget {
  const VaultPage({super.key, required this.onSwitchVault});

  final VoidCallback onSwitchVault;

  @override
  State<VaultPage> createState() => _VaultPageState();
}

class _VaultPageState extends State<VaultPage> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();

  /// 当前所在分组（null 表示根分组）
  KdbxGroup? _group;
  KdbxEntry? _selected;
  bool _showBin = false;
  final Set<String> _collapsed = {};

  VaultSession get _s => context.read<AppState>().session!;

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
    ClipboardService.copy(value, clearAfterSeconds: app.settings.clipboardClearSeconds, sensitive: sensitive);
    showSnack(context, '已复制$label');
  }

  void _open(KdbxGroup g) {
    setState(() {
      _group = g;
      _showBin = false;
      _search.clear();
      // 确保侧栏中能看到这个分组
      for (final p in g.breadcrumbs) {
        _collapsed.remove(p.uuid.uuid);
      }
    });
  }

  bool _goUp() {
    if (_showBin) {
      setState(() => _showBin = false);
      return true;
    }
    if (_search.text.isNotEmpty) {
      setState(() => _search.clear());
      return true;
    }
    final g = _group;
    if (g == null || g.parent == null || g == _s.vault.root) return false;
    setState(() => _group = g.parent == _s.vault.root ? null : g.parent);
    return true;
  }

  Future<void> _newItem(BuildContext context, KdbxGroup group, bool wide) async {
    await showNewItemSheet(
      context,
      _s,
      group,
      onGroupCreated: (g) => setState(() {}),
      onEntryCreated: (e) {
        if (wide) setState(() => _selected = e);
      },
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

  Future<void> _menuAction(String v) async {
    final s = _s;
    switch (v) {
      case 'gen':
        showGenerator(context);
      case 'bin':
        final wide = MediaQuery.sizeOf(context).width >= 720;
        if (wide) {
          setState(() {
            _showBin = true;
            _selected = null;
          });
        } else {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => const RecycleBinPage()));
          if (mounted) setState(() {});
        }
      case 'reload':
        if (s.isDirty) {
          final ok = await confirm(context, '重新加载', '本地未保存的修改将丢失，确定吗？', destructive: true);
          if (!ok) return;
        }
        try {
          await s.reload();
          if (mounted) {
            setState(() {
              _group = null;
              _selected = null;
            });
            showSnack(context, '已从云端重新加载');
          }
        } catch (e) {
          if (mounted) showSnack(context, '加载失败：$e', error: true);
        }
      case 'settings':
        Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage()));
      case 'switch':
        await _lock();
        widget.onSwitchVault();
    }
  }

  List<Widget> _appBarActions(VaultSession s) => [
        _SyncIndicator(session: s),
        IconButton(tooltip: '锁定 (Ctrl+L)', onPressed: _lock, icon: const Icon(Icons.lock_outline)),
        PopupMenuButton<String>(
          onSelected: _menuAction,
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'gen', child: ListTile(leading: Icon(Icons.auto_awesome), title: Text('密码生成器'))),
            PopupMenuItem(value: 'bin', child: ListTile(leading: Icon(Icons.delete_outline), title: Text('回收站'))),
            PopupMenuItem(value: 'reload', child: ListTile(leading: Icon(Icons.refresh), title: Text('从云端重新加载'))),
            PopupMenuItem(value: 'settings', child: ListTile(leading: Icon(Icons.settings_outlined), title: Text('设置'))),
            PopupMenuItem(value: 'switch', child: ListTile(leading: Icon(Icons.swap_horiz), title: Text('切换密码库'))),
          ],
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = app.session!;
    final vault = s.vault;
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 1100;
    final medium = width >= 720 && !wide;

    // 当前分组或选中条目已被删除/移动时回退
    var group = _group ?? vault.root;
    if (group != vault.root && (vault.isHidden(group) || !vault.groups.contains(group))) {
      group = vault.root;
      _group = null;
    }
    if (_selected != null && (vault.isHidden(_selected!) || _selected!.parent == null)) _selected = null;

    final listing = _GroupListing(
      vault: vault,
      group: group,
      query: _search.text,
      selected: wide ? _selected : null,
      showSubgroups: true,
      onOpenGroup: _open,
      onGroupMenu: (g) => showGroupMenu(context, s, g, onDeleted: () => setState(() {})),
      onOpenEntry: (e) {
        if (wide) {
          setState(() => _selected = e);
        } else {
          Navigator.push(context, MaterialPageRoute(builder: (_) => EntryDetailPage(entry: e)))
              .then((_) => mounted ? setState(() {}) : null);
        }
      },
      onEntryMenu: (e) => _entryMenu(e),
      onCopyPassword: (e) => _copy('密码', e.password),
      onCopyTotp: (e) {
        final t = TotpConfig.fromFields(e.allFields);
        if (t != null) _copy('验证码', t.codeAt(DateTime.now()));
      },
      onBreadcrumb: (g) => g == vault.root ? setState(() => _group = null) : _open(g),
      draggable: wide || medium,
    );

    final searchBar = Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: SearchBar(
        controller: _search,
        focusNode: _searchFocus,
        hintText: '在全部 ${vault.entries.length} 个条目中搜索',
        leading: const Icon(Icons.search),
        elevation: const WidgetStatePropertyAll(0),
        backgroundColor: WidgetStatePropertyAll(Theme.of(context).colorScheme.surfaceContainerHigh),
        trailing: [
          if (_search.text.isNotEmpty)
            IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _search.clear())),
        ],
        onChanged: (_) => setState(() {}),
      ),
    );

    final banners = <Widget>[
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
    ];

    final listColumn = Column(
      children: [
        searchBar,
        ...banners,
        Expanded(child: _showBin && (wide || medium) ? const RecycleBinView() : listing),
      ],
    );

    final fab = s.offline || _showBin
        ? null
        : FloatingActionButton.extended(
            onPressed: () => _newItem(context, group, wide),
            icon: const Icon(Icons.add),
            label: const Text('新建'),
          );

    Widget body;
    PreferredSizeWidget appBar;
    if (wide || medium) {
      final sidebar = _GroupTree(
        vault: vault,
        selected: _showBin ? null : group,
        collapsed: _collapsed,
        binSelected: _showBin,
        onSelect: (g) {
          setState(() {
            _group = g == vault.root ? null : g;
            _showBin = false;
            _search.clear();
          });
        },
        onToggle: (g) => setState(() {
          final id = g.uuid.uuid;
          _collapsed.contains(id) ? _collapsed.remove(id) : _collapsed.add(id);
        }),
        onMenu: (g) => showGroupMenu(context, s, g,
            onCreated: (c) => _open(c), onDeleted: () => setState(() => _group = null)),
        onNewGroup: () async {
          final g = await newGroup(context, s, group);
          if (g != null) _open(g);
        },
        onOpenBin: () => setState(() {
          _showBin = true;
          _selected = null;
        }),
        onDropEntry: (e, g) async {
          if (e.parent == g) return;
          vault.moveEntry(e, g);
          s.touch();
          await saveSession(context, s);
          if (context.mounted) showSnack(context, '已移动到"${vault.groupName(g)}"');
        },
      );
      final divider = VerticalDivider(width: 1, color: Theme.of(context).colorScheme.outlineVariant);
      body = Row(
        children: [
          SizedBox(width: wide ? 280 : 250, child: sidebar),
          divider,
          if (wide) ...[
            SizedBox(width: 400, child: listColumn),
            divider,
            Expanded(
              child: _selected == null
                  ? const _EmptyDetail()
                  : EntryDetailView(
                      key: ValueKey(_selected!.uuid.uuid),
                      entry: _selected!,
                      embedded: true,
                      onDeleted: () => setState(() => _selected = null),
                    ),
            ),
          ] else
            Expanded(child: listColumn),
        ],
      );
      appBar = AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(vault.name),
            Text(
              s.source.locationHint,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: _appBarActions(s),
      );
    } else {
      // 手机：文件夹式浏览
      final atRoot = group == vault.root && _search.text.isEmpty;
      body = listColumn;
      appBar = AppBar(
        leading: atRoot ? null : IconButton(icon: const Icon(Icons.arrow_back), onPressed: _goUp),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(group == vault.root ? vault.name : vault.groupName(group), overflow: TextOverflow.ellipsis),
            Text(
              group == vault.root ? s.source.locationHint : '${vault.countIn(group)} 个条目',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          if (group != vault.root)
            IconButton(
              tooltip: '分组操作',
              icon: const Icon(Icons.folder_open_outlined),
              onPressed: () => showGroupMenu(context, s, group,
                  onCreated: (c) => _open(c), onDeleted: () => setState(() => _group = group.parent == vault.root ? null : group.parent)),
            ),
          ..._appBarActions(s),
        ],
      );
    }

    return PopScope(
      canPop: group == vault.root && _search.text.isEmpty && !_showBin,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goUp();
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyF, control: true): () => _searchFocus.requestFocus(),
          const SingleActivator(LogicalKeyboardKey.keyN, control: true): () => _newItem(context, group, wide),
          const SingleActivator(LogicalKeyboardKey.keyL, control: true): _lock,
          const SingleActivator(LogicalKeyboardKey.backspace, alt: true): _goUp,
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(appBar: appBar, floatingActionButton: fab, body: body),
        ),
      ),
    );
  }

  void _entryMenu(KdbxEntry e) {
    final hasTotp = TotpConfig.fromFields(e.allFields) != null;
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      builder: (c) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: KpIcon.of(e, size: 36),
                title: Text(e.title.isEmpty ? '（无标题）' : e.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: e.userName.isEmpty ? null : Text(e.userName),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: const Text('复制用户名'),
                onTap: () {
                  Navigator.pop(c);
                  _copy('用户名', e.userName, sensitive: false);
                },
              ),
              ListTile(
                leading: const Icon(Icons.password_rounded),
                title: const Text('复制密码'),
                onTap: () {
                  Navigator.pop(c);
                  _copy('密码', e.password);
                },
              ),
              if (hasTotp)
                ListTile(
                  leading: const Icon(Icons.timer_outlined),
                  title: const Text('复制验证码'),
                  onTap: () {
                    Navigator.pop(c);
                    _copy('验证码', TotpConfig.fromFields(e.allFields)!.codeAt(DateTime.now()));
                  },
                ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('编辑'),
                onTap: () async {
                  Navigator.pop(c);
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => EntryEditPage(entry: e)));
                  if (mounted) setState(() {});
                },
              ),
              ListTile(
                leading: const Icon(Icons.palette_outlined),
                title: const Text('更换图标'),
                onTap: () async {
                  Navigator.pop(c);
                  await changeIcon(context, _s, e);
                  if (mounted) setState(() {});
                },
              ),
              ListTile(
                leading: const Icon(Icons.drive_file_move_outline),
                title: const Text('移动到…'),
                onTap: () async {
                  Navigator.pop(c);
                  await moveEntryTo(context, _s, e);
                  if (mounted) setState(() {});
                },
              ),
              ListTile(
                leading: Icon(Icons.delete_outline, color: Theme.of(c).colorScheme.error),
                title: Text('删除', style: TextStyle(color: Theme.of(c).colorScheme.error)),
                onTap: () async {
                  Navigator.pop(c);
                  if (await deleteEntry(context, _s, e) && mounted) {
                    setState(() => _selected = _selected == e ? null : _selected);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 分组内容：面包屑 + 子分组 + 条目；有搜索词时显示全库搜索结果
class _GroupListing extends StatelessWidget {
  const _GroupListing({
    required this.vault,
    required this.group,
    required this.query,
    required this.onOpenGroup,
    required this.onGroupMenu,
    required this.onOpenEntry,
    required this.onEntryMenu,
    required this.onCopyPassword,
    required this.onCopyTotp,
    required this.onBreadcrumb,
    this.selected,
    this.showSubgroups = true,
    this.draggable = false,
  });

  final Vault vault;
  final KdbxGroup group;
  final String query;
  final KdbxEntry? selected;
  final bool showSubgroups;
  final bool draggable;
  final void Function(KdbxGroup) onOpenGroup;
  final void Function(KdbxGroup) onGroupMenu;
  final void Function(KdbxEntry) onOpenEntry;
  final void Function(KdbxEntry) onEntryMenu;
  final void Function(KdbxEntry) onCopyPassword;
  final void Function(KdbxEntry) onCopyTotp;
  final void Function(KdbxGroup) onBreadcrumb;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final searching = query.trim().isNotEmpty;
    final subgroups = searching ? const <KdbxGroup>[] : vault.childGroups(group);
    final entries = searching ? vault.search(query) : vault.entriesIn(group);
    final templates = Templates(vault);

    final children = <Widget>[];
    if (!searching && group != vault.root) {
      children.add(_Breadcrumbs(vault: vault, group: group, onTap: onBreadcrumb));
    }
    if (searching) {
      children.add(_SectionLabel('搜索结果 · ${entries.length}'));
    }
    if (subgroups.isNotEmpty && showSubgroups) {
      children.add(_SectionLabel('分组 · ${subgroups.length}'));
      for (final g in subgroups) {
        final n = vault.countIn(g);
        final sub = vault.childGroups(g).length;
        children.add(_Tile(
          leading: KpIcon.of(g, size: 42),
          title: vault.groupName(g),
          subtitle: [if (sub > 0) '$sub 个分组', '$n 个条目'].join(' · '),
          onTap: () => onOpenGroup(g),
          onLongPress: () => onGroupMenu(g),
          trailing: Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
        ));
      }
    }
    if (entries.isNotEmpty) {
      if (!searching) children.add(_SectionLabel('条目 · ${entries.length}'));
      for (final e in entries) {
        final hasTotp = TotpConfig.fromFields(e.allFields) != null;
        final base = entrySubtitle(templates, e);
        final sub = searching
            ? [if (base.isNotEmpty) base, if (e.parent != null && e.parent != vault.root) vault.groupName(e.parent!)].join(' · ')
            : base;
        Widget tile = _Tile(
          leading: KpIcon.of(e, size: 42),
          title: e.title.isEmpty ? '（无标题）' : e.title,
          subtitle: sub,
          selected: selected == e,
          strike: e.isExpired,
          onTap: () => onOpenEntry(e),
          onLongPress: () => onEntryMenu(e),
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
        );
        if (draggable) {
          tile = Draggable<KdbxEntry>(
            data: e,
            dragAnchorStrategy: pointerDragAnchorStrategy,
            feedback: Material(
              elevation: 6,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 14, 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    KpIcon.of(e, size: 28),
                    const SizedBox(width: 8),
                    Text(e.title, style: text.bodyMedium),
                  ],
                ),
              ),
            ),
            childWhenDragging: Opacity(opacity: 0.4, child: tile),
            child: tile,
          );
        }
        children.add(tile);
      }
    }
    if (subgroups.isEmpty && entries.isEmpty) {
      children.add(Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          children: [
            Icon(searching ? Icons.search_off : Icons.folder_open_outlined, size: 56, color: scheme.outlineVariant),
            const SizedBox(height: 12),
            Text(
              searching ? '没有找到"$query"' : '这个分组是空的\n点右下角"新建"添加条目或分组',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ));
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 96),
      children: children,
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.onLongPress,
    this.trailing,
    this.selected = false,
    this.strike = false,
  });

  final Widget leading;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Widget? trailing;
  final bool selected;
  final bool strike;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: GestureDetector(
        onSecondaryTap: onLongPress,
        child: ListTile(
          selected: selected,
          selectedTileColor: scheme.secondaryContainer,
          leading: leading,
          title: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w500,
              decoration: strike ? TextDecoration.lineThrough : null,
            ),
          ),
          subtitle: subtitle.isEmpty ? null : Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: onTap,
          onLongPress: onLongPress,
          trailing: trailing,
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
        ),
      );
}

class _Breadcrumbs extends StatelessWidget {
  const _Breadcrumbs({required this.vault, required this.group, required this.onTap});

  final Vault vault;
  final KdbxGroup group;
  final void Function(KdbxGroup) onTap;

  @override
  Widget build(BuildContext context) {
    final crumbs = group.breadcrumbs;
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        reverse: false,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: crumbs.length,
        separatorBuilder: (_, _) => Icon(Icons.chevron_right, size: 16, color: scheme.onSurfaceVariant),
        itemBuilder: (_, i) {
          final g = crumbs[i];
          final last = i == crumbs.length - 1;
          return Center(
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: last ? null : () => onTap(g),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (i == 0) ...[Icon(Icons.home_outlined, size: 16, color: scheme.primary), const SizedBox(width: 4)],
                    Text(
                      vault.groupName(g),
                      style: TextStyle(
                        color: last ? scheme.onSurface : scheme.primary,
                        fontWeight: last ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 左侧分组树（电脑 / 平板）
class _GroupTree extends StatelessWidget {
  const _GroupTree({
    required this.vault,
    required this.selected,
    required this.collapsed,
    required this.binSelected,
    required this.onSelect,
    required this.onToggle,
    required this.onMenu,
    required this.onNewGroup,
    required this.onOpenBin,
    required this.onDropEntry,
  });

  final Vault vault;
  final KdbxGroup? selected;
  final Set<String> collapsed;
  final bool binSelected;
  final void Function(KdbxGroup) onSelect;
  final void Function(KdbxGroup) onToggle;
  final void Function(KdbxGroup) onMenu;
  final VoidCallback onNewGroup;
  final VoidCallback onOpenBin;
  final void Function(KdbxEntry, KdbxGroup) onDropEntry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final nodes = <({KdbxGroup g, int depth})>[];
    void walk(KdbxGroup g, int depth) {
      for (final c in vault.childGroups(g)) {
        nodes.add((g: c, depth: depth));
        if (!collapsed.contains(c.uuid.uuid)) walk(c, depth + 1);
      }
    }

    walk(vault.root, 0);
    final binCount = (vault.recycledEntries.length + vault.recycledGroups.length);

    Widget node(KdbxGroup g, int depth, {required String label, required int count, bool isRoot = false}) {
      final hasChildren = !isRoot && vault.childGroups(g).isNotEmpty;
      final open = !collapsed.contains(g.uuid.uuid);
      final sel = selected == g;
      return DragTarget<KdbxEntry>(
        onWillAcceptWithDetails: (d) => d.data.parent != g,
        onAcceptWithDetails: (d) => onDropEntry(d.data, g),
        builder: (context, candidates, _) {
          final hover = candidates.isNotEmpty;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
            child: Material(
              color: hover
                  ? scheme.primaryContainer
                  : sel
                      ? scheme.secondaryContainer
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => onSelect(g),
                onLongPress: () => onMenu(g),
                onSecondaryTap: () => onMenu(g),
                child: SizedBox(
                  height: 40,
                  child: Row(
                    children: [
                      SizedBox(width: 4.0 + depth * 16),
                      SizedBox(
                        width: 24,
                        child: hasChildren
                            ? InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () => onToggle(g),
                                child: AnimatedRotation(
                                  turns: open ? 0.25 : 0,
                                  duration: const Duration(milliseconds: 150),
                                  child: Icon(Icons.chevron_right_rounded, size: 20, color: scheme.onSurfaceVariant),
                                ),
                              )
                            : null,
                      ),
                      KpIcon.of(g, size: 26),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: sel || isRoot ? FontWeight.w600 : FontWeight.w400,
                            color: sel ? scheme.onSecondaryContainer : scheme.onSurface,
                          ),
                        ),
                      ),
                      Text('$count', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                      const SizedBox(width: 12),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 8, 4),
          child: Row(
            children: [
              Text('分组',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(color: scheme.primary, fontWeight: FontWeight.w600)),
              const Spacer(),
              IconButton(
                tooltip: '在选中的分组里新建分组',
                icon: const Icon(Icons.create_new_folder_outlined, size: 20),
                onPressed: onNewGroup,
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 12),
            children: [
              node(vault.root, 0, label: vault.name, count: vault.entries.length, isRoot: true),
              for (final n in nodes) node(n.g, n.depth + 1, label: vault.groupName(n.g), count: vault.countIn(n.g)),
            ],
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Material(
            color: binSelected ? scheme.secondaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            child: ListTile(
              dense: true,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              leading: const KpIcon(icon: KdbxIcon.TrashBin, size: 26),
              title: const Text('回收站'),
              trailing: Text('$binCount', style: Theme.of(context).textTheme.labelSmall),
              onTap: onOpenBin,
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyDetail extends StatelessWidget {
  const _EmptyDetail();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.key_rounded, size: 64, color: scheme.outlineVariant),
          const SizedBox(height: 12),
          Text('选择一个条目查看详情', style: TextStyle(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          Text('Ctrl+F 搜索 · Ctrl+N 新建 · Ctrl+L 锁定 · 拖动条目到左侧分组可移动',
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
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
      message: '已同步',
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
      decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(12)),
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
