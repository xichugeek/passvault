import 'package:flutter/material.dart';

import '../core/session.dart';
import 'widgets.dart';

/// 保存并提示结果。冲突时让用户选择处理方式。
Future<bool> saveSession(BuildContext context, VaultSession s) async {
  try {
    final r = await s.save();
    if (!context.mounted) return true;
    if (r == SaveOutcome.merged) {
      showSnack(context, '已与其他设备上的修改合并并保存');
    }
    return true;
  } on SaveConflict catch (e) {
    if (!context.mounted) return false;
    final choice = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('保存未完成'),
        content: Text(e.reason),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, 'later'), child: const Text('稍后再试')),
          TextButton(
            onPressed: () => Navigator.pop(c, 'reload'),
            child: const Text('放弃本地修改并重新加载'),
          ),
        ],
      ),
    );
    if (choice == 'reload') {
      try {
        await s.reload();
        if (context.mounted) showSnack(context, '已重新加载');
      } catch (e2) {
        if (context.mounted) showSnack(context, '重新加载失败：$e2', error: true);
      }
    }
    return false;
  } catch (e) {
    if (context.mounted) {
      showSnack(context, '保存失败：$e\n修改仍在内存中，可稍后重试。', error: true);
    }
    return false;
  }
}
