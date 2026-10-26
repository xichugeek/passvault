import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 指纹/面容/Windows Hello 快速解锁。
///
/// 保存的不是主密码明文，而是 KeePass 复合密钥的哈希（主密码 + 密钥文件）。
/// - 安卓：哈希由 Android Keystore 中"必须生物识别才能使用"的 AES 密钥加密，
///   每次解密都要求指纹验证；新增指纹后密钥自动失效。
/// - Windows：哈希存于系统凭据保管（DPAPI），读取前需 Windows Hello 验证。
class QuickUnlock {
  static const _ch = MethodChannel('passvault/biometric');
  static const _prefix = 'qu_';
  static final _localAuth = LocalAuthentication();
  static const _secure = FlutterSecureStorage();

  static Future<bool> isAvailable() async {
    try {
      if (Platform.isAndroid) {
        return await _ch.invokeMethod<bool>('isAvailable') ?? false;
      }
      if (Platform.isWindows) {
        return await _localAuth.isDeviceSupported();
      }
    } catch (_) {}
    return false;
  }

  static String get methodName => Platform.isWindows ? 'Windows Hello' : '指纹/面容';

  static Future<bool> isEnabled(String sourceId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return prefs.containsKey('$_prefix$sourceId');
  }

  /// 开启快速解锁；会弹出一次生物识别验证。返回是否成功。
  static Future<bool> enable(String sourceId, Uint8List compositeHash) async {
    final prefs = await SharedPreferences.getInstance();
    if (Platform.isAndroid) {
      final r = await _ch.invokeMapMethod<String, String>('encrypt', {
        'data': base64Encode(compositeHash),
        'title': '开启指纹解锁',
      });
      if (r == null) return false;
      await prefs.setString('$_prefix$sourceId', jsonEncode(r));
      return true;
    }
    if (Platform.isWindows) {
      final ok = await _localAuth.authenticate(
        localizedReason: '验证身份以开启 Windows Hello 解锁',
      );
      if (!ok) return false;
      await _secure.write(key: '$_prefix$sourceId', value: base64Encode(compositeHash));
      await prefs.setString('$_prefix$sourceId', 'win');
      return true;
    }
    return false;
  }

  /// 验证并取回复合密钥哈希。用户取消返回 null；
  /// 密钥已失效（例如新增了指纹）会自动关闭快速解锁并抛出 [QuickUnlockInvalidated]。
  static Future<Uint8List?> unlock(String sourceId, {String? title}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final stored = prefs.getString('$_prefix$sourceId');
    if (stored == null) return null;
    if (Platform.isAndroid) {
      final m = jsonDecode(stored) as Map<String, dynamic>;
      try {
        final r = await _ch.invokeMethod<String>('decrypt', {
          'ct': m['ct'],
          'iv': m['iv'],
          'title': title ?? '解锁密码库',
        });
        if (r == null) return null;
        return base64Decode(r);
      } on PlatformException catch (e) {
        if (e.code == 'invalidated') {
          await disable(sourceId);
          throw QuickUnlockInvalidated();
        }
        if (e.code == 'cancelled') return null;
        rethrow;
      }
    }
    if (Platform.isWindows) {
      final ok = await _localAuth.authenticate(
        localizedReason: title ?? '验证身份以解锁密码库',
      );
      if (!ok) return null;
      final v = await _secure.read(key: '$_prefix$sourceId');
      if (v == null) {
        await disable(sourceId);
        throw QuickUnlockInvalidated();
      }
      return base64Decode(v);
    }
    return null;
  }

  static Future<void> disable(String sourceId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix$sourceId');
    if (Platform.isWindows) {
      try {
        await _secure.delete(key: '$_prefix$sourceId');
      } catch (_) {}
    }
  }
}

class QuickUnlockInvalidated implements Exception {
  @override
  String toString() => '快速解锁已失效（设备的生物识别信息有变动），请用主密码解锁后重新开启。';
}
