import 'dart:io';

import 'package:flutter/services.dart';

/// 少量系统能力：敏感剪贴板、自动填充设置、阻止截屏等。
class SystemBridge {
  static const _ch = MethodChannel('passvault/system');

  /// 复制文本。安卓 13+ 会标记为敏感内容，系统剪贴板预览不显示明文。
  static Future<void> copy(String text, {bool sensitive = true}) async {
    if (Platform.isAndroid) {
      try {
        await _ch.invokeMethod('copy', {'text': text, 'sensitive': sensitive});
        return;
      } catch (_) {}
    }
    await Clipboard.setData(ClipboardData(text: text));
  }

  static Future<void> clearClipboard() async {
    if (Platform.isAndroid) {
      try {
        await _ch.invokeMethod('clearClipboard');
        return;
      } catch (_) {}
    }
    await Clipboard.setData(const ClipboardData(text: ''));
  }

  static Future<String?> clipboardText() async =>
      (await Clipboard.getData(Clipboard.kTextPlain))?.text;

  /// 本应用是否已被设为系统自动填充服务
  static Future<bool> isAutofillEnabled() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _ch.invokeMethod<bool>('isAutofillEnabled') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> isAutofillSupported() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _ch.invokeMethod<bool>('isAutofillSupported') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 打开系统设置，让用户选择 PassVault 作为自动填充服务
  static Future<void> requestAutofill() => _ch.invokeMethod('requestAutofill');

  /// 禁止截屏/录屏，并在最近任务中隐藏内容
  static Future<void> setSecureScreen(bool secure) async {
    if (!Platform.isAndroid) return;
    try {
      await _ch.invokeMethod('setSecure', {'secure': secure});
    } catch (_) {}
  }
}
