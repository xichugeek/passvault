import 'dart:io';
import 'dart:typed_data';

import 'package:argon2_ffi_base/argon2_ffi_base.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kdbx/kdbx.dart';
import 'package:passvault/core/argon2_native.dart';
import 'package:passvault/core/matcher.dart';
import 'package:passvault/core/password_generator.dart';
import 'package:passvault/core/templates.dart';
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

    test('没有 .kdbx 后缀的文件也能打开；非 KeePass 文件给出明确提示', () async {
      final dir = Directory.systemTemp.createTempSync('pv');
      final f = File('${dir.path}/james')..writeAsBytesSync(fx('keepassxcpasswords.kdbx'));
      final v = await Vault.open(f.readAsBytesSync(), Credentials(ProtectedValue.fromString('asdf')));
      expect(v.entries, isNotEmpty);
      expect(
        () => Vault.open(Uint8List.fromList('hello world, not a vault'.codeUnits),
            Credentials(ProtectedValue.fromString('asdf'))),
        throwsA(isA<NotKeePassFile>()),
      );
      dir.deleteSync(recursive: true);
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

  group('分组', () {
    Future<Vault> reopen(Vault v) async =>
        Vault.open(await v.save(), Vault.credentials('pw-12345678', null));

    test('保持原有顺序；条目自然排序；上下移动后保存仍保持', () async {
      final v = Vault.create('t', Vault.credentials('pw-12345678', null));
      for (final g in v.childGroups(v.root).toList()) {
        v.deleteGroup(g);
      }
      v.emptyRecycleBin();
      final a = v.createGroup('3.工作');
      v.createGroup('1.金融账户');
      v.createGroup('2.邮箱账户');
      for (final t in ['10.淘宝', '2.京东', '1.支付宝']) {
        v.createEntry(a).setStr(Fields.title, t);
      }
      expect(v.childGroups(v.root).map((g) => g.name.get()), ['3.工作', '1.金融账户', '2.邮箱账户']);
      expect(v.entriesIn(a).map((e) => e.title), ['1.支付宝', '2.京东', '10.淘宝']);
      expect(v.shiftGroup(a, 1), isTrue);
      expect(v.shiftGroup(a, 1), isTrue);
      expect(v.shiftGroup(a, 1), isFalse);
      final v2 = await reopen(v);
      expect(v2.childGroups(v2.root).map((g) => g.name.get()), ['1.金融账户', '2.邮箱账户', '3.工作']);
    });

    test('子分组、移动、回收站、恢复、清空', () async {
      final v = Vault.create('t', Vault.credentials('pw-12345678', null));
      final fin = v.createGroup('金融');
      final pay = v.createGroup('PayPal', parent: fin);
      final e = v.createEntry(pay)..setStr(Fields.title, 'paypal');
      expect(v.countIn(fin), 1);
      expect(v.depth(pay), 1);
      expect(v.groupPath(pay), '金融 / PayPal');
      expect(v.canMoveGroup(fin, pay), isFalse, reason: '不能移到自己的子分组');
      final other = v.createGroup('其它');
      v.moveEntry(e, other);
      expect(v.entriesIn(other), [e]);
      v.deleteGroup(fin);
      expect(v.recycleBin!.name.get(), '回收站');
      expect(v.groups, isNot(contains(fin)));
      expect(v.isHidden(pay), isTrue);
      v.restore(fin);
      expect(v.groups, contains(pay));
      v.deleteEntry(e);
      expect(v.entries, isNot(contains(e)));
      expect(v.recycledEntries, [e]);
      v.emptyRecycleBin();
      expect(v.recycledEntries, isEmpty);
      final v2 = await reopen(v);
      expect(v2.entries.where((x) => x.title == 'paypal'), isEmpty);
    });

    test('超出范围的图标编号不会导致打不开', () async {
      final v = Vault.create('t', Vault.credentials('pw-12345678', null));
      final e = v.createEntry(v.root)..setStr(Fields.title, 'x');
      e.icon.set(KdbxIcon.Money);
      final v2 = await reopen(v);
      expect(v2.entries.single.icon.get(), KdbxIcon.Money);
    });

    test('过期时间保存后保留', () async {
      final v = Vault.create('t', Vault.credentials('pw-12345678', null));
      final e = v.createEntry(v.root)..setStr(Fields.title, 'card');
      e.expiry = DateTime(2030, 5, 31, 23, 59);
      final v2 = await reopen(v);
      final e2 = v2.entries.single;
      expect(e2.expiry, DateTime(2030, 5, 31, 23, 59));
      expect(e2.isExpired, isFalse);
    });
  });

  group('模板（兼容 Keepass2Android）', () {
    test('内置模板写入库中：固定 UUID、_etm_ 字段、模板分组', () async {
      final v = Vault.create('t', Vault.credentials('pw-12345678', null));
      final t = Templates(v);
      expect(t.existing, isEmpty);
      final cc = t.available.firstWhere((x) => x.builtinId == 'creditcard');
      final e = t.createFrom(cc, v.root);
      e.setStr(Fields.title, '招商银行信用卡');
      e.setStr('卡号', '6225 0000 0000 0000');
      e.setStr('CVV', '123', protect: true);
      e.expiry = DateTime(2029, 12, 31);

      final saved = await v.save();
      final v2 = await Vault.open(saved, Vault.credentials('pw-12345678', null));
      final t2 = Templates(v2);
      expect(v2.templatesGroup, isNotNull);
      expect(v2.templatesGroup!.name.get(), '模板');
      expect(v2.groups, isNot(contains(v2.templatesGroup)), reason: '模板分组不在普通列表里');
      expect(v2.entries.map((x) => x.title), ['招商银行信用卡'], reason: '模板条目不参与搜索/填充');
      final tplEntry = v2.templatesGroup!.entries.single;
      expect(uuidToHex(tplEntry.uuid), '49DD48DBFF149445B3392CE90EA75309');
      expect(tplEntry.str('_etm_template'), '1');
      expect(tplEntry.str('_etm_type_CVV'), 'Protected Inline');
      expect(tplEntry.str('_etm_type_@exp_date'), 'Date Time');
      final card = v2.entries.single;
      expect(card.str('_etm_template_uuid'), '49DD48DBFF149445B3392CE90EA75309');
      final tpl = t2.templateOf(card)!;
      expect(tpl.title, '信用卡');
      expect(tpl.fields.map((f) => f.key), ['卡号', 'CVV', 'PIN', '持卡人', '@exp_date']);
      expect(card.icon.get(), KdbxIcon.Homebanking);
      expect(card.visibleCustomFields.keys, isNot(contains('_etm_template_uuid')));
      // 已在库中的模板不会重复出现
      expect(t2.available.where((x) => x.uuidHex == '49DD48DBFF149445B3392CE90EA75309').length, 1);
      // 再用同一模板新建不会重复创建模板条目
      t2.createFrom(t2.available.firstWhere((x) => x.title == '信用卡'), v2.root);
      expect(v2.templatesGroup!.entries.length, 1);
    });

    test('读取 Keepass2Android 写入的模板（字段顺序、类型、下拉选项、分隔线）', () {
      final v = Vault.create('t', Vault.credentials('pw-12345678', null));
      final g = Templates(v).ensureTemplatesGroup();
      final e = v.createEntry(g)..setStr(Fields.title, '护照');
      final f = <String, String>{
        '_etm_template': '1',
        '_etm_title_护照号': '护照号', '_etm_type_护照号': 'Inline', '_etm_position_护照号': '1',
        '_etm_title_国籍': '国籍', '_etm_type_国籍': 'Listbox', '_etm_position_国籍': '2', '_etm_options_国籍': '中国,美国,日本',
        '_etm_title_sep': '有效期', '_etm_type_sep': 'Divider', '_etm_position_sep': '3',
        '_etm_title_@exp_date': '@exp_date', '_etm_type_@exp_date': 'Date Time', '_etm_position_@exp_date': '4',
        '_etm_title_已续签': '已续签', '_etm_type_已续签': 'Checkbox', '_etm_position_已续签': '5',
        '_etm_title_Password': 'Password', '_etm_type_Password': 'Protected Inline', '_etm_position_Password': '0',
      };
      f.forEach(e.setStr);
      final t = Templates.parse(e)!;
      expect(t.fields.map((x) => x.key), ['Password', '护照号', '国籍', 'sep', '@exp_date', '已续签']);
      expect(t.fields[2].type, TFieldType.listbox);
      expect(t.fields[2].options, ['中国', '美国', '日本']);
      expect(t.fields[3].type, TFieldType.divider);
      expect(t.fields[4].displayLabel, '有效期至');
      expect(t.fields[5].type, TFieldType.checkbox);
      expect(t.fields[0].type.isProtected, isTrue);
      expect(Templates(v).available.first.title, '护照');
    });
  });
}
