import 'dart:math';

/// 密码生成选项
class GeneratorOptions {
  final int length;
  final bool upper;
  final bool lower;
  final bool digits;
  final bool symbols;
  final bool excludeAmbiguous;

  const GeneratorOptions({
    this.length = 20,
    this.upper = true,
    this.lower = true,
    this.digits = true,
    this.symbols = true,
    this.excludeAmbiguous = true,
  });

  GeneratorOptions copyWith({
    int? length,
    bool? upper,
    bool? lower,
    bool? digits,
    bool? symbols,
    bool? excludeAmbiguous,
  }) =>
      GeneratorOptions(
        length: length ?? this.length,
        upper: upper ?? this.upper,
        lower: lower ?? this.lower,
        digits: digits ?? this.digits,
        symbols: symbols ?? this.symbols,
        excludeAmbiguous: excludeAmbiguous ?? this.excludeAmbiguous,
      );

  Map<String, dynamic> toJson() => {
        'length': length,
        'upper': upper,
        'lower': lower,
        'digits': digits,
        'symbols': symbols,
        'excludeAmbiguous': excludeAmbiguous,
      };

  factory GeneratorOptions.fromJson(Map<String, dynamic> j) => GeneratorOptions(
        length: (j['length'] as int?) ?? 20,
        upper: (j['upper'] as bool?) ?? true,
        lower: (j['lower'] as bool?) ?? true,
        digits: (j['digits'] as bool?) ?? true,
        symbols: (j['symbols'] as bool?) ?? true,
        excludeAmbiguous: (j['excludeAmbiguous'] as bool?) ?? true,
      );
}

class PasswordGenerator {
  static const _upper = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  static const _lower = 'abcdefghijklmnopqrstuvwxyz';
  static const _digits = '0123456789';
  static const _symbols = r'!@#$%^&*()-_=+[]{};:,.<>/?~';
  static const _ambiguous = 'Il1O0o|`\'"';

  static final Random _rng = Random.secure();

  /// 生成密码；保证每个选中的字符类别至少出现一次。
  static String generate(GeneratorOptions o) {
    final sets = <String>[];
    String filter(String s) => o.excludeAmbiguous
        ? s.split('').where((c) => !_ambiguous.contains(c)).join()
        : s;
    if (o.upper) sets.add(filter(_upper));
    if (o.lower) sets.add(filter(_lower));
    if (o.digits) sets.add(filter(_digits));
    if (o.symbols) sets.add(filter(_symbols));
    if (sets.isEmpty) sets.add(filter(_lower));

    final length = max(o.length, sets.length);
    final all = sets.join();
    final chars = <String>[
      for (final s in sets) s[_rng.nextInt(s.length)],
      for (var i = sets.length; i < length; i++) all[_rng.nextInt(all.length)],
    ];
    // Fisher–Yates 洗牌
    for (var i = chars.length - 1; i > 0; i--) {
      final j = _rng.nextInt(i + 1);
      final t = chars[i];
      chars[i] = chars[j];
      chars[j] = t;
    }
    return chars.join();
  }

  /// 粗略估算熵（比特），用于强度条显示。
  static double entropyBits(String pw) {
    if (pw.isEmpty) return 0;
    var pool = 0;
    if (pw.contains(RegExp(r'[a-z]'))) pool += 26;
    if (pw.contains(RegExp(r'[A-Z]'))) pool += 26;
    if (pw.contains(RegExp(r'[0-9]'))) pool += 10;
    if (pw.contains(RegExp(r'[^a-zA-Z0-9]'))) pool += 32;
    if (pool == 0) pool = 26;
    final unique = pw.split('').toSet().length;
    // 重复字符多时打折
    final effectiveLen = (pw.length + unique) / 2;
    return effectiveLen * log(pool) / ln2;
  }

  /// 0–4 强度等级
  static int strengthLevel(String pw) {
    final b = entropyBits(pw);
    if (b < 28) return 0;
    if (b < 45) return 1;
    if (b < 65) return 2;
    if (b < 90) return 3;
    return 4;
  }

  static const strengthLabels = ['很弱', '弱', '一般', '强', '很强'];
}
