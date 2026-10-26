import 'dart:async';

import '../platform/system_bridge.dart';

/// 复制敏感内容并在指定秒数后自动清空剪贴板（仅当剪贴板内容仍是我们复制的那条）。
class ClipboardService {
  static Timer? _timer;
  static String? _lastCopied;

  static Future<void> copy(String text, {int clearAfterSeconds = 30, bool sensitive = true}) async {
    await SystemBridge.copy(text, sensitive: sensitive);
    _timer?.cancel();
    _lastCopied = text;
    if (clearAfterSeconds > 0 && sensitive) {
      _timer = Timer(Duration(seconds: clearAfterSeconds), clearIfOurs);
    }
  }

  static Future<void> clearIfOurs() async {
    final mine = _lastCopied;
    _lastCopied = null;
    _timer?.cancel();
    if (mine == null) return;
    try {
      final current = await SystemBridge.clipboardText();
      // 安卓 10+ 后台无法读取剪贴板，读不到时也直接清空
      if (current == null || current == mine) {
        await SystemBridge.clearClipboard();
      }
    } catch (_) {
      await SystemBridge.clearClipboard();
    }
  }
}
