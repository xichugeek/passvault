import 'dart:async';

import 'package:flutter/widgets.dart';

import 'core/clipboard_service.dart';
import 'core/session.dart';
import 'core/settings.dart';

/// 全局状态：设置 + 当前解锁的会话 + 自动锁定。
class AppState extends ChangeNotifier with WidgetsBindingObserver {
  AppState(this.settings) {
    WidgetsBinding.instance.addObserver(this);
    settings.addListener(notifyListeners);
  }

  final Settings settings;
  VaultSession? _session;
  Timer? _lockTimer;
  DateTime? _backgroundedAt;

  VaultSession? get session => _session;
  bool get isUnlocked => _session != null;

  void setSession(VaultSession s) {
    _session?.removeListener(notifyListeners);
    _session?.close();
    _session = s;
    s.addListener(notifyListeners);
    settings.addRecent(s.source);
    userActivity();
    notifyListeners();
  }

  /// 锁定：释放内存中的密码库。有未保存修改时由调用方先处理。
  void lock() {
    _lockTimer?.cancel();
    final s = _session;
    if (s == null) return;
    s.removeListener(notifyListeners);
    s.close();
    _session = null;
    ClipboardService.clearIfOurs();
    notifyListeners();
  }

  /// 任何用户操作都会重置自动锁定计时
  void userActivity() {
    _lockTimer?.cancel();
    final m = settings.autoLockMinutes;
    if (_session == null || m <= 0) return;
    _lockTimer = Timer(Duration(minutes: m), _autoLock);
  }

  void _autoLock() {
    final s = _session;
    if (s == null) return;
    if (s.isDirty || s.saving) {
      // 有未保存修改时先尝试保存，成功后再锁
      s.save().then((_) => lock()).catchError((_) {
        // 保存失败就不锁，避免丢数据；下次活动后重新计时
        userActivity();
      });
      return;
    }
    lock();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _backgroundedAt ??= DateTime.now();
      if (settings.lockOnBackground && _session != null && !(_session!.isDirty)) {
        // 给系统文件选择器、指纹弹窗等短暂离开留出 15 秒余量
        _lockTimer?.cancel();
        _lockTimer = Timer(const Duration(seconds: 15), _autoLock);
      }
    } else if (state == AppLifecycleState.resumed) {
      final bg = _backgroundedAt;
      _backgroundedAt = null;
      final m = settings.autoLockMinutes;
      if (bg != null && m > 0 && DateTime.now().difference(bg).inMinutes >= m) {
        _autoLock();
      } else {
        userActivity();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _lockTimer?.cancel();
    super.dispose();
  }
}
