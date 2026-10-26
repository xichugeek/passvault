import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:kdbx/kdbx.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../platform/android_saf.dart';
import 'vault.dart';
import 'vault_source.dart';

enum SaveOutcome { saved, merged, savedLocallyOnly }

class SaveConflict implements Exception {
  SaveConflict(this.reason);
  final String reason;
  @override
  String toString() => reason;
}

/// 一个已解锁密码库的会话：负责加载、保存、冲突合并、离线缓存与自动锁定。
class VaultSession extends ChangeNotifier {
  VaultSession._(this.source, this.vault, this._credentials, this._loadedHash,
      {this.offline = false});

  final VaultSource source;
  Vault vault;
  Credentials _credentials;
  String _loadedHash;

  /// 云端文件读取失败时使用本地缓存，处于只读状态
  final bool offline;

  bool _saving = false;
  bool get saving => _saving;

  DateTime? lastSaved;
  String? lastError;

  bool get isDirty => vault.isDirty;

  Uint8List get compositeHash => _credentials.getHash();

  /// 打开：优先读取原文件，失败时回退到本地缓存（只读）。
  static Future<VaultSession> open(
    VaultSource source,
    Credentials credentials, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    Uint8List bytes;
    var offline = false;
    try {
      bytes = await source.read().timeout(timeout);
    } catch (e) {
      final cached = await _readCache(source);
      if (cached == null) rethrow;
      debugPrint('读取原文件失败，使用本地缓存: $e');
      bytes = cached;
      offline = true;
    }
    final vault = await Vault.open(bytes, credentials);
    if (!offline) unawaited(_writeCache(source, bytes));
    return VaultSession._(
      source,
      vault,
      credentials,
      _hash(bytes),
      offline: offline,
    );
  }

  /// 新建密码库并写入 [source]
  static Future<VaultSession> create(
    VaultSource source,
    String name,
    Credentials credentials,
  ) async {
    final vault = Vault.create(name, credentials);
    final bytes = await vault.save();
    await source.write(bytes);
    await _writeCache(source, bytes);
    return VaultSession._(source, vault, credentials, _hash(bytes));
  }

  /// 保存。若文件在其他设备上被修改过，会先自动合并再写回。
  Future<SaveOutcome> save() async {
    if (offline) {
      throw SaveConflict('当前为离线只读模式（无法访问云端文件），请联网后重新打开再修改。');
    }
    if (_saving) {
      // 等待正在进行的保存结束后再保存一次
      while (_saving) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
    _saving = true;
    lastError = null;
    notifyListeners();
    try {
      var outcome = SaveOutcome.saved;
      Uint8List? remote;
      try {
        remote = await source.read().timeout(const Duration(seconds: 20));
      } catch (e) {
        remote = null; // 文件不存在或暂时读不到，直接写
      }
      if (remote != null && _hash(remote) != _loadedHash) {
        // 其他设备修改过 → 合并
        final KdbxFile other;
        try {
          other = await Vault.format.read(remote, _credentials);
        } on KdbxInvalidKeyException {
          throw SaveConflict('云端密码库的主密码已在其他设备上修改，请重新打开密码库。');
        }
        try {
          vault.file.merge(other);
          outcome = SaveOutcome.merged;
        } catch (e) {
          throw SaveConflict('云端文件已被其他设备修改，自动合并失败：$e');
        } finally {
          other.dispose();
        }
      }
      final bytes = await vault.save();
      await source.write(bytes);
      _loadedHash = _hash(bytes);
      lastSaved = DateTime.now();
      unawaited(_writeCache(source, bytes));
      return outcome;
    } catch (e) {
      lastError = e.toString();
      rethrow;
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  /// 从云端重新加载（放弃本地未保存修改）
  Future<void> reload() async {
    final bytes = await source.read();
    final v = await Vault.open(bytes, _credentials);
    vault.dispose();
    vault = v;
    _loadedHash = _hash(bytes);
    unawaited(_writeCache(source, bytes));
    notifyListeners();
  }

  /// 修改主密码
  Future<void> changeMasterKey(Credentials newCredentials) async {
    vault.file.credentials = newCredentials;
    _credentials = newCredentials;
    vault.file.body.meta.masterKeyChanged.setToNow();
    await save();
  }

  void touch() => notifyListeners();

  void close() {
    vault.dispose();
  }

  static String _hash(Uint8List b) => sha256.convert(b).toString();

  static Future<File> _cacheFile(VaultSource s) async {
    final dir = await getApplicationSupportDirectory();
    final d = Directory(p.join(dir.path, 'cache'));
    if (!await d.exists()) await d.create(recursive: true);
    return File(p.join(d.path, '${s.id}.kdbx'));
  }

  static Future<Uint8List?> _readCache(VaultSource s) async {
    try {
      final f = await _cacheFile(s);
      if (await f.exists()) return await f.readAsBytes();
    } catch (_) {}
    return null;
  }

  static Future<void> _writeCache(VaultSource s, Uint8List bytes) async {
    try {
      final f = await _cacheFile(s);
      await f.writeAsBytes(bytes, flush: true);
    } catch (_) {}
  }

  static Future<void> deleteCache(VaultSource s) async {
    try {
      final f = await _cacheFile(s);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}

/// 读取密钥文件内容（Windows 路径或安卓 URI）
Future<Uint8List> readKeyFile(String location) async {
  if (location.startsWith('content://')) return AndroidSaf.read(location);
  return File(location).readAsBytes();
}
