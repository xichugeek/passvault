import 'package:flutter/material.dart';
import 'package:kdbx/kdbx.dart';

import '../core/session.dart';
import '../core/templates.dart';
import '../core/vault.dart';
import 'entry_edit_page.dart';
import 'kp_icons.dart';
import 'save_helper.dart';
import 'sheet.dart';
import 'widgets.dart';

/// 输入名称
Future<String?> promptName(BuildContext context, String title, {String initial = '', String hint = '名称'}) {
  final c = TextEditingController(text: initial);
  c.selection = TextSelection(baseOffset: 0, extentOffset: initial.length);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
          onPressed: () => Navigator.pop(ctx, c.text.trim()),
          child: const Text('确定'),
        ),
      ],
    ),
  ).then((v) => v == null || v.isEmpty ? null : v);
}

/// 选择目标分组（树形缩进显示，保持原有顺序）
Future<KdbxGroup?> pickGroup(
  BuildContext context,
  Vault vault, {
  required String title,
  bool Function(KdbxGroup g)? enabled,
  KdbxGroup? current,
}) {
  final items = [vault.root, ...vault.groups];
  return showListSheet<KdbxGroup>(
    context,
    contentHeight: 56.0 + items.length * 48 + 24,
    builder: (c, scroll) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(title, style: Theme.of(c).textTheme.titleLarge),
          ),
          Expanded(
            child: ListView.builder(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
              itemCount: items.length,
              itemBuilder: (c, i) {
                final g = items[i];
                final ok = enabled?.call(g) ?? true;
                final depth = g == vault.root ? 0 : vault.depth(g) + 1;
                return ListTile(
                  enabled: ok,
                  selected: g == current,
                  dense: true,
                  visualDensity: const VisualDensity(vertical: -1),
                  contentPadding: EdgeInsets.only(left: 12.0 + depth * 20, right: 12),
                  leading: KpIcon.of(g, size: 30, dimmed: !ok),
                  title: Text(vault.groupName(g), style: Theme.of(c).textTheme.bodyLarge?.copyWith(
                      color: ok ? null : Theme.of(c).disabledColor)),
                  trailing: g == current ? const Icon(Icons.check) : null,
                  onTap: ok ? () => Navigator.pop(c, g) : null,
                );
              },
            ),
          ),
        ],
      ),
  );
}

Future<KdbxGroup?> newGroup(BuildContext context, VaultSession s, KdbxGroup parent) async {
  final name = await promptName(
    context,
    parent == s.vault.root ? '新建分组' : '在"${s.vault.groupName(parent)}"中新建分组',
    hint: '分组名称',
  );
  if (name == null || !context.mounted) return null;
  final g = s.vault.createGroup(name, parent: parent, icon: KdbxIcon.Folder);
  s.touch();
  await saveSession(context, s);
  return g;
}

Future<void> renameGroup(BuildContext context, VaultSession s, KdbxGroup g) async {
  final name = await promptName(context, '重命名分组', initial: g.name.get() ?? '');
  if (name == null || name == g.name.get() || !context.mounted) return;
  g.name.set(name);
  s.touch();
  await saveSession(context, s);
}

Future<void> changeIcon(BuildContext context, VaultSession s, KdbxObject o) async {
  final choice = await pickIcon(context, s.vault.file, current: o);
  if (choice == null || !context.mounted) return;
  choice.applyTo(o);
  s.touch();
  await saveSession(context, s);
}

Future<bool> deleteGroup(BuildContext context, VaultSession s, KdbxGroup g) async {
  final v = s.vault;
  final n = v.countIn(g);
  final permanent = v.inRecycleBin(g);
  final ok = await confirm(
    context,
    permanent ? '永久删除分组' : '删除分组',
    permanent
        ? '"${v.groupName(g)}"及其中 $n 个条目将被永久删除，无法恢复。'
        : '"${v.groupName(g)}"及其中 $n 个条目将移入回收站，可以随时恢复。',
    ok: permanent ? '永久删除' : '删除',
    destructive: true,
  );
  if (!ok || !context.mounted) return false;
  v.deleteGroup(g);
  s.touch();
  await saveSession(context, s);
  return true;
}

Future<void> moveGroupTo(BuildContext context, VaultSession s, KdbxGroup g) async {
  final v = s.vault;
  final to = await pickGroup(
    context,
    v,
    title: '把"${v.groupName(g)}"移动到',
    enabled: (t) => v.canMoveGroup(g, t),
    current: g.parent,
  );
  if (to == null || !context.mounted) return;
  v.moveGroup(g, to);
  s.touch();
  await saveSession(context, s);
}

Future<void> moveEntryTo(BuildContext context, VaultSession s, KdbxEntry e) async {
  final v = s.vault;
  final to = await pickGroup(context, v, title: '把"${e.title}"移动到', current: e.parent);
  if (to == null || to == e.parent || !context.mounted) return;
  v.moveEntry(e, to);
  s.touch();
  await saveSession(context, s);
  if (context.mounted) showSnack(context, '已移动到"${v.groupName(to)}"');
}

Future<bool> deleteEntry(BuildContext context, VaultSession s, KdbxEntry e) async {
  final permanent = s.vault.inRecycleBin(e);
  final ok = await confirm(
    context,
    permanent ? '永久删除条目' : '删除条目',
    permanent ? '"${e.title}"将被永久删除，无法恢复。' : '将"${e.title}"移入回收站？',
    ok: permanent ? '永久删除' : '删除',
    destructive: true,
  );
  if (!ok || !context.mounted) return false;
  s.vault.deleteEntry(e);
  s.touch();
  await saveSession(context, s);
  return true;
}

/// 分组的操作菜单
Future<void> showGroupMenu(
  BuildContext context,
  VaultSession s,
  KdbxGroup g, {
  void Function(KdbxGroup created)? onCreated,
  VoidCallback? onDeleted,
}) async {
  final v = s.vault;
  final isRoot = g == v.root;
  final siblings = g.parent == null ? <KdbxGroup>[] : v.childGroups(g.parent!);
  final idx = siblings.indexOf(g);
  final action = await showMenuSheet<String>(
    context,
    children: (c) => [
            ListTile(
              leading: KpIcon.of(g, size: 36),
              title: Text(v.groupName(g), style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('${v.countIn(g)} 个条目'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.create_new_folder_outlined),
              title: const Text('新建子分组'),
              onTap: () => Navigator.pop(c, 'new'),
            ),
            if (!isRoot) ...[
              ListTile(
                leading: const Icon(Icons.drive_file_rename_outline),
                title: const Text('重命名'),
                onTap: () => Navigator.pop(c, 'rename'),
              ),
              ListTile(
                leading: const Icon(Icons.palette_outlined),
                title: const Text('更换图标'),
                onTap: () => Navigator.pop(c, 'icon'),
              ),
              if (idx > 0)
                ListTile(
                  leading: const Icon(Icons.arrow_upward),
                  title: const Text('上移'),
                  onTap: () => Navigator.pop(c, 'up'),
                ),
              if (idx >= 0 && idx < siblings.length - 1)
                ListTile(
                  leading: const Icon(Icons.arrow_downward),
                  title: const Text('下移'),
                  onTap: () => Navigator.pop(c, 'down'),
                ),
              ListTile(
                leading: const Icon(Icons.drive_file_move_outline),
                title: const Text('移动到…'),
                onTap: () => Navigator.pop(c, 'move'),
              ),
              ListTile(
                leading: Icon(Icons.delete_outline, color: Theme.of(c).colorScheme.error),
                title: Text('删除', style: TextStyle(color: Theme.of(c).colorScheme.error)),
                onTap: () => Navigator.pop(c, 'delete'),
              ),
            ],
          ],
  );
  if (action == null || !context.mounted) return;
  switch (action) {
    case 'new':
      final created = await newGroup(context, s, g);
      if (created != null) onCreated?.call(created);
    case 'rename':
      await renameGroup(context, s, g);
    case 'icon':
      await changeIcon(context, s, g);
    case 'up':
    case 'down':
      if (v.shiftGroup(g, action == 'up' ? -1 : 1)) {
        s.touch();
        await saveSession(context, s);
      }
    case 'move':
      await moveGroupTo(context, s, g);
    case 'delete':
      if (await deleteGroup(context, s, g)) onDeleted?.call();
  }
}

/// "新建"菜单：标准条目、各类模板、新建分组
Future<void> showNewItemSheet(
  BuildContext context,
  VaultSession s,
  KdbxGroup group, {
  void Function(KdbxGroup created)? onGroupCreated,
  void Function(KdbxEntry created)? onEntryCreated,
}) async {
  final templates = Templates(s.vault).available;
  // 选项：标准条目 + 模板 + 分组
  final options = <({Widget icon, String title, String subtitle, Object result})>[
    (icon: const KpIcon(icon: KdbxIcon.Key, size: 40), title: '标准条目', subtitle: '用户名、密码、网址、备注', result: 'standard'),
    for (final t in templates)
      (
        icon: KpIcon(icon: t.icon, custom: t.entry?.customIcon, size: 40),
        title: t.title,
        subtitle: t.fields
            .where((f) => f.type != TFieldType.divider)
            .map((f) => f.displayLabel)
            .take(4)
            .join('、'),
        result: t,
      ),
    (icon: const KpIcon(icon: KdbxIcon.Folder, size: 40), title: '分组', subtitle: '在当前位置新建一个分组', result: 'group'),
  ];
  // 宽屏（电脑、平板）两列排列，一屏显示完整
  final twoCols = MediaQuery.sizeOf(context).width >= 520;
  final rows = twoCols ? (options.length / 2).ceil() : options.length;
  final picked = await showListSheet<Object>(
    context,
    contentHeight: 76.0 + rows * (twoCols ? 68 : 72) + 24,
    builder: (c, scroll) {
      final text = Theme.of(c).textTheme;
      Widget tile(({Widget icon, String title, String subtitle, Object result}) o) => InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => Navigator.pop(c, o.result),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                children: [
                  o.icon,
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(o.title, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w500)),
                        const SizedBox(height: 2),
                        Text(o.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodySmall?.copyWith(color: Theme.of(c).colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
      return ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 2),
            child: Text('新建', style: text.titleLarge),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Text('保存到：${s.vault.groupName(group)}', style: text.bodySmall),
          ),
          if (twoCols)
            for (var i = 0; i < options.length; i += 2)
              Row(
                children: [
                  Expanded(child: tile(options[i])),
                  const SizedBox(width: 8),
                  Expanded(child: i + 1 < options.length ? tile(options[i + 1]) : const SizedBox()),
                ],
              )
          else
            for (final o in options) tile(o),
        ],
      );
    },
  );
  if (picked == null || !context.mounted) return;
  if (picked == 'group') {
    final g = await newGroup(context, s, group);
    if (g != null) onGroupCreated?.call(g);
    return;
  }
  final created = await Navigator.push<KdbxEntry>(
    context,
    MaterialPageRoute(
      builder: (_) => EntryEditPage(
        initialGroup: group,
        template: picked is EntryTemplate ? picked : null,
      ),
    ),
  );
  if (created != null) onEntryCreated?.call(created);
}
