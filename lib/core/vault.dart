import 'dart:typed_data';

import 'package:kdbx/kdbx.dart';

import 'argon2_native.dart';

/// KeePass 中常用的标准字段名
class Fields {
  static const title = 'Title';
  static const userName = 'UserName';
  static const password = 'Password';
  static const url = 'URL';
  static const notes = 'Notes';
  static const otp = 'otp';

  static const standard = {title, userName, password, url, notes};

  /// 安卓 App 关联字段（兼容 KeePassDX）
  static const androidApp = 'AndroidApp';
}

/// 对 KdbxFile 的轻量封装：打开、新建、增删改查、保存。
class Vault {
  Vault._(this.file);

  final KdbxFile file;

  static KdbxFormat? _format;

  /// 优先使用原生 Argon2，加载失败则回退纯 Dart 实现（慢但可用）。
  static KdbxFormat get format =>
      _format ??= KdbxFormat(NativeArgon2.tryLoad());

  /// 测试或特殊场景下替换格式实现
  static set format(KdbxFormat f) => _format = f;

  static bool get usingNativeArgon2 => format.argon2.isFfi;

  static Credentials credentials(String password, Uint8List? keyFile) =>
      Credentials.composite(
        password.isEmpty && keyFile != null
            ? null
            : ProtectedValue.fromString(password),
        keyFile,
      );

  static Future<Vault> open(Uint8List bytes, Credentials credentials) async {
    final file = await format.read(bytes, credentials);
    return Vault._(file);
  }

  /// 新建 KDBX 4 数据库（Argon2d，与 KeePass 默认设置一致）
  static Vault create(String name, Credentials credentials) {
    final file = format.create(credentials, name, generator: 'PassVault');
    final root = file.body.rootGroup;
    // 预置几个常用分组
    for (final g in const ['常用', '社交', '购物', '金融', '工作']) {
      file.createGroup(parent: root, name: g);
    }
    return Vault._(file);
  }

  Future<Uint8List> save() => file.save();

  String get name =>
      file.body.meta.databaseName.get() ?? file.body.rootGroup.name.get() ?? '密码库';

  KdbxGroup get root => file.body.rootGroup;

  KdbxGroup? get recycleBin => file.recycleBin;

  bool get isDirty => file.isDirty;

  bool _inRecycleBin(KdbxObject o) {
    final bin = recycleBin;
    if (bin == null) return false;
    KdbxGroup? p = o is KdbxGroup ? o : o.parent;
    while (p != null) {
      if (p.uuid == bin.uuid) return true;
      p = p.parent;
    }
    return false;
  }

  /// 所有有效条目（不含回收站）
  List<KdbxEntry> get entries => root
      .getAllEntries()
      .where((e) => !e.isHistoryEntry && !_inRecycleBin(e))
      .toList();

  /// 所有分组（不含根组与回收站），按路径排序
  List<KdbxGroup> get groups {
    final list = root
        .getAllGroups()
        .where((g) => g != root && !_inRecycleBin(g))
        .toList();
    list.sort((a, b) => groupPath(a).compareTo(groupPath(b)));
    return list;
  }

  String groupPath(KdbxGroup g) => g.breadcrumbs
      .where((x) => x != root)
      .map((x) => x.name.get() ?? '')
      .join(' / ');

  List<KdbxEntry> search(String query, {KdbxGroup? inGroup}) {
    final base = inGroup == null
        ? entries
        : inGroup
            .getAllEntries()
            .where((e) => !_inRecycleBin(e))
            .toList();
    final q = query.trim().toLowerCase();
    final list = q.isEmpty
        ? base
        : base.where((e) {
            final hay = [
              e.str(Fields.title),
              e.str(Fields.userName),
              e.str(Fields.url),
              e.str(Fields.notes),
              e.tags.get() ?? '',
            ].join('\n').toLowerCase();
            return q.split(RegExp(r'\s+')).every(hay.contains);
          }).toList();
    list.sort((a, b) =>
        a.str(Fields.title).toLowerCase().compareTo(b.str(Fields.title).toLowerCase()));
    return list;
  }

  KdbxEntry createEntry(KdbxGroup group) {
    final e = KdbxEntry.create(file, group);
    group.addEntry(e);
    return e;
  }

  KdbxGroup createGroup(String name, {KdbxGroup? parent}) =>
      file.createGroup(parent: parent ?? root, name: name);

  /// 删除条目：移入回收站（与 KeePass 行为一致）
  void deleteEntry(KdbxEntry e) => file.deleteEntry(e);

  void moveEntry(KdbxEntry e, KdbxGroup to) => file.move(e, to);

  KdbxEntry? findEntry(String uuid) {
    for (final e in entries) {
      if (e.uuid.uuid == uuid) return e;
    }
    return null;
  }

  void dispose() => file.dispose();
}

/// 条目字段读写的便捷方法
extension EntryX on KdbxEntry {
  String str(String key) {
    final v = getString(KdbxKey(key));
    return v?.getText() ?? '';
  }

  void setStr(String key, String value, {bool protect = false}) {
    final k = KdbxKey(key);
    final old = getString(k)?.getText() ?? '';
    if (old == value && (getString(k) != null || value.isEmpty)) return;
    setString(
      k,
      protect ? ProtectedValue.fromString(value) : PlainValue(value),
    );
  }

  String get title => str(Fields.title);
  String get userName => str(Fields.userName);
  String get password => str(Fields.password);
  String get url => str(Fields.url);
  String get notes => str(Fields.notes);

  /// 自定义字段（非标准字段）
  Map<String, String> get customFields {
    final m = <String, String>{};
    for (final e in stringEntries) {
      if (!Fields.standard.contains(e.key.key)) {
        m[e.key.key] = e.value?.getText() ?? '';
      }
    }
    return m;
  }

  bool isProtected(String key) => getString(KdbxKey(key)) is ProtectedValue;

  /// 全部字符串字段（用于 TOTP 解析等）
  Map<String, String> get allFields => {
        for (final e in stringEntries) e.key.key: e.value?.getText() ?? '',
      };

  DateTime? get modified => times.lastModificationTime.get()?.toLocal();
}
