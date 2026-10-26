import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:argon2_ffi_base/argon2_ffi_base.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:kdbx/kdbx.dart' show KeyEncrypterKdf, EncryptAesArgs;

typedef _HashNative = Int32 Function(
  Pointer<Uint8> pwd,
  Uint32 pwdlen,
  Pointer<Uint8> salt,
  Uint32 saltlen,
  Uint32 mCost,
  Uint32 tCost,
  Uint32 parallelism,
  Uint32 version,
  Uint32 type,
  Pointer<Uint8> out,
  Uint32 outlen,
);
typedef _HashDart = int Function(
  Pointer<Uint8> pwd,
  int pwdlen,
  Pointer<Uint8> salt,
  int saltlen,
  int mCost,
  int tCost,
  int parallelism,
  int version,
  int type,
  Pointer<Uint8> out,
  int outlen,
);

typedef _AesNative = Int32 Function(Pointer<Uint8> key, Pointer<Uint8> data, Uint64 rounds);
typedef _AesDart = int Function(Pointer<Uint8> key, Pointer<Uint8> data, int rounds);

/// 原生 Argon2 实现（C 参考实现，通过 FFI 调用）。
/// 比纯 Dart 实现快 10 倍以上，解锁时间从数秒降到 1 秒以内。
class NativeArgon2 extends Argon2 {
  NativeArgon2._(this._hash);

  final _HashDart _hash;

  /// 尝试加载原生库；失败返回 null，由调用方回退到纯 Dart 实现。
  static NativeArgon2? tryLoad({String? overridePath}) {
    try {
      final lib = DynamicLibrary.open(overridePath ?? _isolatePath ?? _libName());
      final fn = lib.lookupFunction<_HashNative, _HashDart>('pv_argon2_hash');
      final native = NativeArgon2._(fn);
      // 同时接管 AES-KDF（旧版 KeePass 数据库默认使用，轮数可达数百万）
      final libPath = overridePath ?? _isolatePath ?? _libName();
      KeyEncrypterKdf.aesKdfOverride = (args) => _aesKdf(libPath, args);
      return native;
    } catch (e) {
      debugPrint('NativeArgon2 unavailable: $e');
      return null;
    }
  }

  static String _libName() {
    if (Platform.isAndroid || Platform.isLinux) return 'libpv_argon2.so';
    if (Platform.isWindows) return 'pv_argon2.dll';
    if (Platform.isMacOS) return 'libpv_argon2.dylib';
    throw UnsupportedError('unsupported platform');
  }

  @override
  bool get isFfi => true;

  @override
  bool get isImplemented => true;

  @override
  Uint8List argon2(Argon2Arguments args) {
    final pwd = malloc<Uint8>(args.key.isEmpty ? 1 : args.key.length);
    final salt = malloc<Uint8>(args.salt.length);
    final out = malloc<Uint8>(args.length);
    try {
      pwd.asTypedList(args.key.length).setAll(0, args.key);
      salt.asTypedList(args.salt.length).setAll(0, args.salt);
      final rc = _hash(
        pwd,
        args.key.length,
        salt,
        args.salt.length,
        args.memory,
        args.iterations,
        args.parallelism,
        args.version,
        args.type,
        out,
        args.length,
      );
      if (rc != 0) {
        throw StateError('Argon2 失败，错误码 $rc');
      }
      return Uint8List.fromList(out.asTypedList(args.length));
    } finally {
      // 清零敏感内存
      pwd.asTypedList(args.key.isEmpty ? 1 : args.key.length).fillRange(
          0, args.key.isEmpty ? 1 : args.key.length, 0);
      out.asTypedList(args.length).fillRange(0, args.length, 0);
      malloc.free(pwd);
      malloc.free(salt);
      malloc.free(out);
    }
  }

  @override
  Future<Uint8List> argon2Async(Argon2Arguments args) async {
    // 放到后台 isolate，避免界面卡顿
    final path = _isolatePath ?? _libName();
    return Isolate.run(() {
      final a = NativeArgon2.tryLoad(overridePath: path);
      if (a == null) throw StateError('无法在后台加载 Argon2');
      return a.argon2(args);
    });
  }

  static Future<Uint8List> _aesKdf(String libPath, EncryptAesArgs args) {
    final key = args.encryptionKey!;
    final data = args.key;
    final rounds = args.rounds!;
    return Isolate.run(() {
      final lib = DynamicLibrary.open(libPath);
      final fn = lib.lookupFunction<_AesNative, _AesDart>('pv_aes_kdf');
      final k = malloc<Uint8>(32);
      final d = malloc<Uint8>(32);
      try {
        k.asTypedList(32).setAll(0, key);
        d.asTypedList(32).setAll(0, data);
        fn(k, d, rounds);
        final out = Uint8List.fromList(d.asTypedList(32));
        return Uint8List.fromList(crypto.sha256.convert(out).bytes);
      } finally {
        k.asTypedList(32).fillRange(0, 32, 0);
        d.asTypedList(32).fillRange(0, 32, 0);
        malloc.free(k);
        malloc.free(d);
      }
    });
  }

  /// 测试时可指定库的绝对路径
  static String? _isolatePath;
  static set libraryPathOverride(String? p) => _isolatePath = p;
}
