
import 'package:flutter/services.dart';

/// 安卓存储访问框架（SAF）。通过系统文件选择器打开 Google Drive 等云盘里的文件，
/// 并获得长期读写权限，修改后直接写回原文件。
class AndroidSaf {
  static const _ch = MethodChannel('passvault/saf');

  /// 选择一个已有文件，返回 {uri, name, provider}；用户取消返回 null。
  static Future<Map<String, String>?> openDocument({bool persist = true}) async {
    final r = await _ch.invokeMapMethod<String, String>(
        'openDocument', {'persist': persist});
    return r;
  }

  /// 新建文件（用于创建新密码库），返回 {uri, name, provider}
  static Future<Map<String, String>?> createDocument(String suggestedName) =>
      _ch.invokeMapMethod<String, String>(
          'createDocument', {'name': suggestedName});

  static Future<Uint8List> read(String uri) async {
    final r = await _ch.invokeMethod<Uint8List>('read', {'uri': uri});
    if (r == null) throw StateError('读取失败');
    return r;
  }

  static Future<void> write(String uri, Uint8List bytes) =>
      _ch.invokeMethod('write', {'uri': uri, 'bytes': bytes});

  static Future<void> releasePermission(String uri) =>
      _ch.invokeMethod('release', {'uri': uri});
}
