import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'password_generator.dart';
import 'vault_source.dart';

/// 应用设置与最近打开的密码库，保存在 SharedPreferences（主程序与自动填充共用）。
class Settings extends ChangeNotifier {
  Settings._(this._prefs) {
    _load();
  }

  final SharedPreferences _prefs;

  static Future<Settings> load() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return Settings._(prefs);
  }

  ThemeMode themeMode = ThemeMode.system;
  int seedColor = 0xFF3D5AFE;
  int autoLockMinutes = 5; // 0 = 从不
  bool lockOnBackground = false;
  int clipboardClearSeconds = 30; // 0 = 不清除
  bool secureScreen = true;
  bool autofillAutoPickSingle = true;
  bool showPasswordsInList = false;
  GeneratorOptions generator = const GeneratorOptions();
  List<VaultSource> recents = [];

  void _load() {
    themeMode = ThemeMode.values[_prefs.getInt('themeMode') ?? 0];
    seedColor = _prefs.getInt('seedColor') ?? seedColor;
    autoLockMinutes = _prefs.getInt('autoLockMinutes') ?? 5;
    lockOnBackground = _prefs.getBool('lockOnBackground') ?? false;
    clipboardClearSeconds = _prefs.getInt('clipboardClearSeconds') ?? 30;
    secureScreen = _prefs.getBool('secureScreen') ?? true;
    autofillAutoPickSingle = _prefs.getBool('autofillAutoPickSingle') ?? true;
    showPasswordsInList = _prefs.getBool('showPasswordsInList') ?? false;
    final g = _prefs.getString('generator');
    if (g != null) {
      try {
        generator = GeneratorOptions.fromJson(jsonDecode(g) as Map<String, dynamic>);
      } catch (_) {}
    }
    recents = [];
    for (final s in _prefs.getStringList('recents') ?? const <String>[]) {
      try {
        recents.add(VaultSource.fromJson(jsonDecode(s) as Map<String, dynamic>));
      } catch (_) {}
    }
  }

  Future<void> reload() async {
    await _prefs.reload();
    _load();
    notifyListeners();
  }

  Future<void> update(void Function(Settings s) change) async {
    change(this);
    await _prefs.setInt('themeMode', themeMode.index);
    await _prefs.setInt('seedColor', seedColor);
    await _prefs.setInt('autoLockMinutes', autoLockMinutes);
    await _prefs.setBool('lockOnBackground', lockOnBackground);
    await _prefs.setInt('clipboardClearSeconds', clipboardClearSeconds);
    await _prefs.setBool('secureScreen', secureScreen);
    await _prefs.setBool('autofillAutoPickSingle', autofillAutoPickSingle);
    await _prefs.setBool('showPasswordsInList', showPasswordsInList);
    await _prefs.setString('generator', jsonEncode(generator.toJson()));
    notifyListeners();
  }

  VaultSource? get lastSource => recents.isEmpty ? null : recents.first;

  Future<void> addRecent(VaultSource s) async {
    recents.removeWhere((r) => r.id == s.id);
    recents.insert(0, s);
    if (recents.length > 8) recents = recents.sublist(0, 8);
    await _saveRecents();
  }

  Future<void> removeRecent(VaultSource s) async {
    recents.removeWhere((r) => r.id == s.id);
    await _saveRecents();
  }

  Future<void> _saveRecents() async {
    await _prefs.setStringList(
        'recents', recents.map((r) => jsonEncode(r.toJson())).toList());
    notifyListeners();
  }

  /// 每个密码库可选的密钥文件路径/URI（只记位置，不存内容）
  String? keyFileFor(String sourceId) => _prefs.getString('kf_$sourceId');

  Future<void> setKeyFileFor(String sourceId, String? location) async {
    if (location == null) {
      await _prefs.remove('kf_$sourceId');
    } else {
      await _prefs.setString('kf_$sourceId', location);
    }
  }
}
