import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// TOTP 配置。兼容 KeePassXC / Keepass2Android 的 `otp` 字段（otpauth:// 链接），
/// 以及 KeePass 2.47+ 的 `TimeOtp-Secret-Base32` 等字段、KeeOtp 的 `TOTP Seed`。
class TotpConfig {
  final Uint8List secret;
  final int digits;
  final int period;
  final String algorithm; // SHA1 / SHA256 / SHA512

  const TotpConfig({
    required this.secret,
    this.digits = 6,
    this.period = 30,
    this.algorithm = 'SHA1',
  });

  /// 从条目的字段表中解析 TOTP；没有则返回 null。
  static TotpConfig? fromFields(Map<String, String> fields) {
    final otp = fields['otp'];
    if (otp != null && otp.trim().isNotEmpty) {
      final c = parse(otp.trim());
      if (c != null) return c;
    }
    final b32 = fields['TimeOtp-Secret-Base32'];
    if (b32 != null && b32.trim().isNotEmpty) {
      final secret = base32Decode(b32);
      if (secret != null) {
        final alg = (fields['TimeOtp-Algorithm'] ?? 'HMAC-SHA-1')
            .toUpperCase()
            .replaceAll('HMAC-', '')
            .replaceAll('-', '');
        return TotpConfig(
          secret: secret,
          digits: int.tryParse(fields['TimeOtp-Length'] ?? '') ?? 6,
          period: int.tryParse(fields['TimeOtp-Period'] ?? '') ?? 30,
          algorithm: alg,
        );
      }
    }
    final seed = fields['TOTP Seed'];
    if (seed != null && seed.trim().isNotEmpty) {
      final secret = base32Decode(seed);
      if (secret != null) {
        var digits = 6, period = 30;
        final settings = fields['TOTP Settings'];
        if (settings != null) {
          final parts = settings.split(';');
          if (parts.isNotEmpty) period = int.tryParse(parts[0]) ?? 30;
          if (parts.length > 1) digits = int.tryParse(parts[1]) ?? 6;
        }
        return TotpConfig(secret: secret, digits: digits, period: period);
      }
    }
    return null;
  }

  /// 解析 otpauth://totp/...?secret=XXX 或纯 Base32 密钥。
  static TotpConfig? parse(String value) {
    if (value.toLowerCase().startsWith('otpauth://')) {
      final uri = Uri.tryParse(value);
      if (uri == null || uri.host.toLowerCase() != 'totp') return null;
      final q = uri.queryParameters.map((k, v) => MapEntry(k.toLowerCase(), v));
      final secret = base32Decode(q['secret'] ?? '');
      if (secret == null) return null;
      return TotpConfig(
        secret: secret,
        digits: int.tryParse(q['digits'] ?? '') ?? 6,
        period: int.tryParse(q['period'] ?? '') ?? 30,
        algorithm: (q['algorithm'] ?? 'SHA1').toUpperCase(),
      );
    }
    // KeePassXC 旧格式 key=XXX&step=30&size=6
    if (value.contains('key=')) {
      final q = Uri.splitQueryString(value);
      final secret = base32Decode(q['key'] ?? '');
      if (secret == null) return null;
      return TotpConfig(
        secret: secret,
        digits: int.tryParse(q['size'] ?? '') ?? 6,
        period: int.tryParse(q['step'] ?? '') ?? 30,
      );
    }
    final secret = base32Decode(value);
    if (secret == null) return null;
    return TotpConfig(secret: secret);
  }

  /// 生成指定时间的验证码。
  String codeAt(DateTime time) {
    final counter = time.millisecondsSinceEpoch ~/ 1000 ~/ period;
    final msg = ByteData(8)..setInt64(0, counter);
    final Hash h;
    switch (algorithm) {
      case 'SHA256':
        h = sha256;
        break;
      case 'SHA512':
        h = sha512;
        break;
      default:
        h = sha1;
    }
    final mac = Hmac(h, secret).convert(msg.buffer.asUint8List()).bytes;
    final offset = mac.last & 0x0f;
    final bin = ((mac[offset] & 0x7f) << 24) |
        ((mac[offset + 1] & 0xff) << 16) |
        ((mac[offset + 2] & 0xff) << 8) |
        (mac[offset + 3] & 0xff);
    var mod = 1;
    for (var i = 0; i < digits; i++) {
      mod *= 10;
    }
    return (bin % mod).toString().padLeft(digits, '0');
  }

  /// 当前周期剩余秒数
  int secondsRemaining(DateTime time) =>
      period - (time.millisecondsSinceEpoch ~/ 1000) % period;

  static Uint8List? base32Decode(String input) {
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    final s = input.toUpperCase().replaceAll(RegExp(r'[\s=-]'), '');
    if (s.isEmpty) return null;
    final out = <int>[];
    var buffer = 0, bits = 0;
    for (final ch in s.split('')) {
      final v = alphabet.indexOf(ch);
      if (v < 0) return null;
      buffer = (buffer << 5) | v;
      bits += 5;
      if (bits >= 8) {
        bits -= 8;
        out.add((buffer >> bits) & 0xff);
      }
    }
    return out.isEmpty ? null : Uint8List.fromList(out);
  }
}
