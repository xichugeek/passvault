import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../platform/android_saf.dart';

/// 密码库文件的来源：Windows 本地路径（含 Google Drive 电脑版同步目录），
/// 或安卓系统文件选择器拿到的文档 URI（含 Google Drive）。
abstract class VaultSource {
  const VaultSource();

  String get kind;

  /// 唯一标识，用于最近文件、快速解锁等
  String get id;

  String get displayName;

  /// 位置描述，例如 "Google Drive" 或文件夹路径
  String get locationHint;

  Future<Uint8List> read();

  Future<void> write(Uint8List bytes);

  Map<String, dynamic> toJson();

  static VaultSource fromJson(Map<String, dynamic> j) {
    switch (j['kind']) {
      case LocalFileSource.kindName:
        return LocalFileSource(j['path'] as String);
      case SafSource.kindName:
        return SafSource(
          uri: j['uri'] as String,
          name: j['name'] as String? ?? 'vault.kdbx',
          provider: j['provider'] as String? ?? '',
        );
    }
    throw ArgumentError('未知的来源类型: ${j['kind']}');
  }

  static String hashId(String raw) =>
      sha256.convert(utf8.encode(raw)).toString().substring(0, 16);
}

class LocalFileSource extends VaultSource {
  static const kindName = 'local';

  const LocalFileSource(this.path);

  final String path;

  @override
  String get kind => kindName;

  @override
  String get id => VaultSource.hashId('$kindName:$path');

  @override
  String get displayName => p.basename(path);

  @override
  String get locationHint {
    final dir = p.dirname(path);
    if (dir.toLowerCase().contains('google drive') ||
        dir.toLowerCase().contains('my drive') ||
        dir.contains('我的云端硬盘')) {
      return 'Google Drive · $dir';
    }
    return dir;
  }

  @override
  Future<Uint8List> read() => File(path).readAsBytes();

  /// 先写临时文件再替换，避免写到一半断电/同步冲突导致库损坏
  @override
  Future<void> write(Uint8List bytes) async {
    final target = File(path);
    final tmp = File('$path.pvtmp');
    try {
      await tmp.writeAsBytes(bytes, flush: true);
      try {
        await tmp.rename(path);
        return;
      } on FileSystemException {
        // 某些同步盘不支持覆盖式重命名，退回直接写入
      }
      await target.writeAsBytes(bytes, flush: true);
      if (await tmp.exists()) await tmp.delete();
    } catch (_) {
      if (await tmp.exists()) {
        try {
          await tmp.delete();
        } catch (_) {}
      }
      rethrow;
    }
  }

  @override
  Map<String, dynamic> toJson() => {'kind': kind, 'path': path};
}

class SafSource extends VaultSource {
  static const kindName = 'saf';

  const SafSource({required this.uri, required this.name, this.provider = ''});

  final String uri;
  final String name;

  /// 文档提供方（authority），用于显示 "Google Drive" 等
  final String provider;

  @override
  String get kind => kindName;

  @override
  String get id => VaultSource.hashId('$kindName:$uri');

  @override
  String get displayName => name;

  @override
  String get locationHint {
    final a = provider.isEmpty ? Uri.tryParse(uri)?.authority ?? '' : provider;
    if (a.contains('google.android.apps.docs')) return 'Google Drive';
    if (a.contains('com.android.externalstorage')) return '手机存储';
    if (a.contains('downloads')) return '下载';
    if (a.contains('onedrive')) return 'OneDrive';
    if (a.contains('nextcloud')) return 'Nextcloud';
    if (a.contains('dropbox')) return 'Dropbox';
    return a;
  }

  @override
  Future<Uint8List> read() => AndroidSaf.read(uri);

  @override
  Future<void> write(Uint8List bytes) => AndroidSaf.write(uri, bytes);

  @override
  Map<String, dynamic> toJson() =>
      {'kind': kind, 'uri': uri, 'name': name, 'provider': provider};
}
