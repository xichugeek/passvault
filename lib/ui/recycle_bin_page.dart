import 'package:flutter/material.dart';
import 'package:kdbx/kdbx.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../core/vault.dart';
import 'entry_detail.dart';
import 'kp_icons.dart';
import 'save_helper.dart';
import 'widgets.dart';

/// 回收站内容（电脑端嵌在中间栏，手机端作为独立页面）
class RecycleBinView extends StatelessWidget {
  const RecycleBinView({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = app.session!;
    final v = s.vault;
    final groups = v.recycledGroups;
    final entries = v.recycledEntries;
    final scheme = Theme.of(context).colorScheme;

    Future<void> restore(KdbxObject o) async {
      v.restore(o);
      s.touch();
      await saveSession(context, s);
      if (context.mounted) showSnack(context, '已恢复到"${v.groupName(o.parent!)}"');
    }

    Future<void> purge(KdbxObject o, String name) async {
      final ok = await confirm(context, '永久删除', '"$name"将被永久删除，无法恢复。', ok: '永久删除', destructive: true);
      if (!ok || !context.mounted) return;
      if (o is KdbxGroup) {
        v.deleteGroup(o);
      } else if (o is KdbxEntry) {
        v.deleteEntry(o);
      }
      s.touch();
      await saveSession(context, s);
    }

    Widget actions(KdbxObject o, String name) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(tooltip: '恢复', icon: const Icon(Icons.restore), onPressed: () => restore(o)),
            IconButton(
              tooltip: '永久删除',
              icon: Icon(Icons.delete_forever_outlined, color: scheme.error),
              onPressed: () => purge(o, name),
            ),
          ],
        );

    if (groups.isEmpty && entries.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_outline, size: 56, color: scheme.outlineVariant),
            const SizedBox(height: 12),
            Text('回收站是空的', style: TextStyle(color: scheme.onSurfaceVariant)),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 32),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
          child: Row(
            children: [
              Expanded(
                child: Text('回收站 · ${groups.length + entries.length} 项',
                    style: Theme.of(context).textTheme.titleSmall),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: scheme.error),
                onPressed: () async {
                  final ok = await confirm(context, '清空回收站', '回收站中的所有内容将被永久删除，无法恢复。',
                      ok: '清空', destructive: true);
                  if (!ok || !context.mounted) return;
                  v.emptyRecycleBin();
                  s.touch();
                  await saveSession(context, s);
                },
                icon: const Icon(Icons.delete_sweep_outlined),
                label: const Text('清空'),
              ),
            ],
          ),
        ),
        for (final g in groups)
          ListTile(
            leading: KpIcon.of(g, size: 40),
            title: Text(v.groupName(g)),
            subtitle: Text('分组 · ${g.getAllEntries().length} 个条目'),
            trailing: actions(g, v.groupName(g)),
          ),
        for (final e in entries)
          ListTile(
            leading: KpIcon.of(e, size: 40),
            title: Text(e.title.isEmpty ? '（无标题）' : e.title),
            subtitle: e.userName.isEmpty ? null : Text(e.userName),
            trailing: actions(e, e.title),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => EntryDetailPage(entry: e))),
          ),
      ],
    );
  }
}

class RecycleBinPage extends StatelessWidget {
  const RecycleBinPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('回收站')),
        body: const RecycleBinView(),
      );
}
