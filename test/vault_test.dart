import 'dart:io';
import 'dart:typed_data';

import 'package:argon2_ffi_base/argon2_ffi_base.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kdbx/kdbx.dart';
import 'package:passvault/core/argon2_native.dart';
import 'package:passvault/core/matcher.dart';
import 'package:passvault/core/password_generator.dart';
import 'package:passvault/core/totp.dart';
import 'package:passvault/core/vault.dart';
import 'package:pointycastle/export.dart' as pc;

Uint8List fx(String name) => File('test/fixtures/$name').readAsBytesSync();

void main() {
  final libPath = '${Directory.current.path}/build/native/libpv_argon2.so';
  final hasNative = File(libPath).existsSync();

  setUpAll(() {
    if (hasNative) {
      NativeArgon2.libraryPathOverride = libPath;
      Vault.format = KdbxFormat(NativeArgon2.tryLoad());
    }
  });

  group('原生 Argon2', () {
    test('与纯 Dart 实现结果一致（d / i / id）', () {
      final native = NativeArgon2.tryLoad();
      expect(native, isNotNull, reason: '需要先编译 native 库');
      for (final type in [0, 1, 2]) {
        final args = Argon2Arguments(
          Uint8List.fromList(List.generate(32, (i) => i)),
          Uint8List.fromList(List.generate(32, (i) => 255 - i)),
          1024, // KiB
          3,
          32,
          2,
          type,
          0x13,
        );
        final expected = (pc.Argon2BytesGenerator()
              ..init(pc.Argon2Parameters(type, args.salt,
                  desiredKeyLength: 32, iterations: 3, memory: 1024, lanes: 2, version: 0x13)))
            .process(args.key);
        expect(native!.argon2(args), expected, reason: 'type=$type');
      }
    });

    test('AES-KDF 原生实现与纯 Dart 一致', () async {
      final key = Uint8List.fromList(List.generate(32, (i) => i * 7 % 256));
      final data = Uint8List.fromList(List.generate(32, (i) => i * 13 % 256));
      final args = EncryptAesArgs(key, data, 5000);
      final native = await KeyEncrypterKdf.aesKdfOverride!(args);
      // 纯 Dart 参考实现
      final cipher = pc.ECBBlockCipher(pc.AESEngine())..init(true, pc.KeyParameter(key));
      var a = Uint8List.fromList(data), b = Uint8List(32);
      for (var i = 0; i < 5000; i++) {
        cipher.processBlock(a, 0, b, 0);
        cipher.processBlock(a, 16, b, 16);
        final t = a;
        a = b;
        b = t;
      }
      expect(native, pc.SHA256Digest().process(a));
    });
  }, skip: hasNative ? false : '未找到 build/native/libpv_argon2.so');

  group('KeePass 文件兼容性', () {
    final cases = {
      'keepassxcpasswords.kdbx': 'KeePassXC 生成（KDBX4 Argon2）',
      'kdbx4_keeweb.kdbx': 'KeeWeb 生成（KDBX4）',
      'chacha20.kdbx': 'ChaCha20 加密',
      'aeskdf.kdbx': 'AES-KDF',
      'keepass2test.kdbx': 'KeePass 2.x 生成',
    };
    for (final c in cases.entries) {
      test('打开 → 修改 → 保存 → 重新打开：${c.value}', () async {
        final cred = Credentials(ProtectedValue.fromString('asdf'));
        final v = await Vault.open(fx(c.key), cred);
        final before = v.entries.length;
        final e = v.createEntry(v.root);
        e.setStr(Fields.title, '测试条目 中文');
        e.setStr(Fields.userName, 'user@example.com');
        e.setStr(Fields.password, 'p@ss 密码 🔑', protect: true);
        final bytes = await v.save();
        final v2 = await Vault.open(bytes, Credentials(ProtectedValue.fromString('asdf')));
        expect(v2.entries.length, before + 1);
        final e2 = v2.entries.firstWhere((x) => x.title == '测试条目 中文');
        expect(e2.password, 'p@ss 密码 🔑');
        expect(e2.isProtected(Fields.password), isTrue);
      });
    }

    test('Argon2id 数据库（KeePassXC 新版默认）', () async {
      // 新建 Argon2id 库：修改 KDF 参数后保存再打开
      final v = Vault.create('id', Vault.credentials('pw-12345678', null));
      final header = v.file.header;
      final params = header.readKdfParameters;
      KdfField.uuid.write(params, KdbxUuid('nimLGVbbR3OyPfw+xvCh5g==').toBytes());
      header.writeKdfParameters(params);
      final bytes = await v.save();
      final v2 = await Vault.open(bytes, Vault.credentials('pw-12345678', null));
      expect(v2.name, 'id');
      expect(
        () => Vault.open(bytes, Vault.credentials('wrong-password', null)),
        throwsA(isA<KdbxInvalidKeyException>()),
      );
    });

    test('KDBX 3（KeePass 2.x 旧格式）', () async {
      final v = await Vault.open(fx('FooBar.kdbx'), Credentials(ProtectedValue.fromString('FooBar')));
      expect(v.entries, isNotEmpty);
      final bytes = await v.save();
      await Vault.open(bytes, Credentials(ProtectedValue.fromString('FooBar')));
    });

    test('主密码 + 密钥文件', () async {
      final v = await Vault.open(
        fx('password-and-keyfile.kdbx'),
        Vault.credentials('asdf', fx('password-and-keyfile.key')),
      );
      expect(v.root.entries, hasLength(2));
    });

    test('错误密码抛出 KdbxInvalidKeyException', () async {
      expect(
        () => Vault.open(fx('keepassxcpasswords.kdbx'), Credentials(ProtectedValue.fromString('wrong'))),
        throwsA(isA<KdbxInvalidKeyException>()),
      );
    });

    test('复合密钥哈希可用于快速解锁并保存', () async {
      final cred = Credentials(ProtectedValue.fromString('asdf'));
      final v = await Vault.open(fx('keepassxcpasswords.kdbx'), cred);
      final hash = cred.getHash();
      final v2 = await Vault.open(fx('keepassxcpasswords.kdbx'), Credentials.fromHash(hash));
      v2.createEntry(v2.root).setStr(Fields.title, 'x');
      final saved = await v2.save();
      await Vault.open(saved, Credentials(ProtectedValue.fromString('asdf')));
      expect(v.entries.length, v2.entries.length - 1);
    });
  });

  group('新建与两端同步合并', () {
    test('新建密码库可被重新打开', () async {
      final v = Vault.create('我的密码库', Vault.credentials('correct horse battery', null));
      expect(v.groups.map((g) => g.name.get()), contains('社交'));
      final bytes = await v.save();
      final v2 = await Vault.open(bytes, Vault.credentials('correct horse battery', null));
      expect(v2.name, '我的密码库');
    });

    test('两台设备分别新增条目后合并，不丢数据', () async {
      final pw = Vault.credentials('pw-12345678', null);
      final base = Vault.create('库', pw);
      final baseBytes = await base.save();

      // 设备 A（Windows）
      final a = await Vault.open(baseBytes, Vault.credentials('pw-12345678', null));
      a.createEntry(a.root).setStr(Fields.title, '来自电脑');
      final aBytes = await a.save();

      // 设备 B（手机）基于旧版本修改
      final b = await Vault.open(baseBytes, Vault.credentials('pw-12345678', null));
      b.createEntry(b.root).setStr(Fields.title, '来自手机');

      // B 保存时发现云端已变化 → 合并
      final remote = await Vault.format.read(aBytes, Vault.credentials('pw-12345678', null));
      b.file.merge(remote);
      final merged = await b.save();
      final m = await Vault.open(merged, Vault.credentials('pw-12345678', null));
      final titles = m.entries.map((e) => e.title).toSet();
      expect(titles, containsAll(['来自电脑', '来自手机']));
    });

    test('两台设备修改同一条目时保留较新的版本', () async {
      final base = Vault.create('库', Vault.credentials('pw-12345678', null));
      final e0 = base.createEntry(base.root)..setStr(Fields.title, '邮箱');
      e0.setStr(Fields.password, 'old', protect: true);
      final baseBytes = await base.save();

      final a = await Vault.open(baseBytes, Vault.credentials('pw-12345678', null));
      a.entries.single.setStr(Fields.password, 'from-a', protect: true);
      final aBytes = await a.save();

      await Future<void>.delayed(const Duration(milliseconds: 1100));
      final b = await Vault.open(baseBytes, Vault.credentials('pw-12345678', null));
      b.entries.single.setStr(Fields.password, 'from-b-newer', protect: true);

      final remote = await Vault.format.read(aBytes, Vault.credentials('pw-12345678', null));
      b.file.merge(remote);
      final m = await Vault.open(await b.save(), Vault.credentials('pw-12345678', null));
      expect(m.entries.single.password, 'from-b-newer');
    });
  });

  group('TOTP', () {
    // RFC 6238 测试向量（SHA1，8 位）
    test('RFC 6238', () {
      final c = TotpConfig(
        secret: Uint8List.fromList('12345678901234567890'.codeUnits),
        digits: 8,
      );
      expect(c.codeAt(DateTime.fromMillisecondsSinceEpoch(59 * 1000, isUtc: true)), '94287082');
      expect(c.codeAt(DateTime.fromMillisecondsSinceEpoch(1111111109 * 1000, isUtc: true)), '07081804');
      expect(c.codeAt(DateTime.fromMillisecondsSinceEpoch(2000000000 * 1000, isUtc: true)), '69279037');
    });

    test('解析 otpauth 链接与各客户端字段', () {
      final c = TotpConfig.parse('otpauth://totp/GitHub:me?secret=JBSWY3DPEHPK3PXP&issuer=GitHub&digits=6&period=30')!;
      expect(c.digits, 6);
      expect(TotpConfig.fromFields({'TimeOtp-Secret-Base32': 'JBSWY3DPEHPK3PXP'}), isNotNull);
      expect(TotpConfig.fromFields({'TOTP Seed': 'JBSWY3DPEHPK3PXP', 'TOTP Settings': '30;6'}), isNotNull);
      expect(TotpConfig.fromFields({'otp': 'key=JBSWY3DPEHPK3PXP&step=30&size=6'}), isNotNull);
      expect(TotpConfig.parse('not a secret!!'), isNull);
    });
  });

  group('自动填充匹配', () {
    late Vault v;
    setUp(() {
      v = Vault.create('t', Vault.credentials('pw-12345678', null));
      void add(String t, Map<String, String> f) {
        final e = v.createEntry(v.root)..setStr(Fields.title, t);
        f.forEach(e.setStr);
      }

      add('GitHub', {Fields.url: 'https://github.com/login', Fields.userName: 'me'});
      add('微信', {Fields.url: 'androidapp://com.tencent.mm'});
      add('淘宝', {Fields.androidApp: 'com.taobao.taobao'});
      add('京东', {Fields.url: 'https://passport.jd.com'});
      add('银行', {Fields.url: 'https://bank.example.com.cn'});
      add('其它', {});
    });

    List<String> titles(List<KdbxEntry> l) => l.map((e) => e.title).toList();

    test('按网页域名匹配（含子域名）', () {
      expect(titles(EntryMatcher.match(v.entries, webDomain: 'github.com')), ['GitHub']);
      expect(titles(EntryMatcher.match(v.entries, webDomain: 'm.jd.com')), ['京东']);
      expect(titles(EntryMatcher.match(v.entries, webDomain: 'www.bank.example.com.cn')), ['银行']);
    });

    test('按 App 包名匹配（Keepass2Android / KeePassDX 两种格式）', () {
      expect(titles(EntryMatcher.match(v.entries, packageName: 'com.tencent.mm')), ['微信']);
      expect(titles(EntryMatcher.match(v.entries, packageName: 'com.taobao.taobao')), ['淘宝']);
      expect(titles(EntryMatcher.match(v.entries, packageName: 'com.github.android')), ['GitHub']);
      expect(titles(EntryMatcher.match(v.entries, packageName: 'com.jingdong.app.mall')), ['京东']);
    });

    test('关联后下次自动匹配', () {
      final other = v.entries.firstWhere((e) => e.title == '其它');
      expect(EntryMatcher.match(v.entries, packageName: 'com.foo.bar'), isEmpty);
      EntryMatcher.linkApp(other, 'com.foo.bar');
      expect(titles(EntryMatcher.match(v.entries, packageName: 'com.foo.bar')), ['其它']);
      EntryMatcher.linkDomain(other, 'login.foo.org');
      expect(titles(EntryMatcher.match(v.entries, webDomain: 'foo.org')), ['其它']);
    });
  });

  group('密码生成器', () {
    test('长度与字符类别', () {
      for (var i = 0; i < 200; i++) {
        final p = PasswordGenerator.generate(const GeneratorOptions(length: 16));
        expect(p.length, 16);
        expect(p, matches(RegExp(r'[A-Z]')));
        expect(p, matches(RegExp(r'[a-z]')));
        expect(p, matches(RegExp(r'[0-9]')));
        expect(p, matches(RegExp(r'[^A-Za-z0-9]')));
        expect(p, isNot(matches(RegExp(r'[Il1O0o]'))));
      }
      expect(PasswordGenerator.strengthLevel('123456'), 0);
      expect(PasswordGenerator.strengthLevel(PasswordGenerator.generate(const GeneratorOptions())), 4);
    });
  });
}
