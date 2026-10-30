import 'dart:typed_data';

import 'package:kdbx/kdbx.dart';

import 'argon2_native.dart';

class NotKeePassFile implements Exception {
  const NotKeePassFile();
  @override
  String toString() => '这个文件不是 KeePass 密码库，请选择你的密码库文件（可以没有 .kdbx 后缀）';
}

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

  /// KeePass 文件签名（KDBX 2.x 起相同）
  static const _signature = [0x03, 0xD9, 0xA2, 0x9A, 0x67, 0xFB, 0x4B, 0xB5];

  /// 根据文件头判断是不是 KeePass 密码库（与文件名后缀无关）
  static bool looksLikeKdbx(Uint8List bytes) {
    if (bytes.length < _signature.length) return false;
    for (var i = 0; i < _signature.length; i++) {
      if (bytes[i] != _signature[i]) return false;
    }
    return true;
  }

  static Future<Vault> open(Uint8List bytes, Credentials credentials) async {
    if (!looksLikeKdbx(bytes)) throw const NotKeePassFile();
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

  /// 模板分组（KeePass 元数据 EntryTemplatesGroup，Keepass2Android 也用它）
  KdbxGroup? get templatesGroup {
    final id = file.body.meta.entryTemplatesGroup.get();
    if (id == null) return null;
    for (final g in root.getAllGroups()) {
      if (g.uuid == id) return g;
    }
    return null;
  }

  bool get isDirty => file.isDirty;

  static bool _under(KdbxObject o, KdbxGroup? ancestor) {
    if (ancestor == null) return false;
    KdbxGroup? p = o is KdbxGroup ? o : o.parent;
    while (p != null) {
      if (p.uuid == ancestor.uuid) return true;
      p = p.parent;
    }
    return false;
  }

  bool inRecycleBin(KdbxObject o) => _under(o, recycleBin);

  bool inTemplates(KdbxObject o) => _under(o, templatesGroup);

  /// 回收站、模板分组不参与普通浏览、搜索和自动填充
  bool isHidden(KdbxObject o) => inRecycleBin(o) || inTemplates(o);

  bool isSpecialGroup(KdbxGroup g) =>
      g.uuid == recycleBin?.uuid || g.uuid == templatesGroup?.uuid;

  /// 所有有效条目（不含回收站与模板）
  List<KdbxEntry> get entries => root
      .getAllEntries()
      .where((e) => !e.isHistoryEntry && !isHidden(e))
      .toList();

  /// 所有分组（不含根组、回收站、模板），按树的先序遍历，保持原有顺序
  List<KdbxGroup> get groups {
    final out = <KdbxGroup>[];
    void walk(KdbxGroup g) {
      for (final c in childGroups(g)) {
        out.add(c);
        walk(c);
      }
    }

    walk(root);
    return out;
  }

  /// 直接子分组（保持 KeePass 文件中的顺序）
  List<KdbxGroup> childGroups(KdbxGroup g) =>
      g.groups.where((c) => !isSpecialGroup(c)).toList();

  /// 分组内直接包含的条目（按标题自然排序）
  List<KdbxEntry> entriesIn(KdbxGroup g) {
    final list = g.entries.where((e) => !e.isHistoryEntry).toList();
    list.sort((a, b) => naturalCompare(a.title, b.title));
    return list;
  }

  /// 分组（含子分组）中的条目总数
  int countIn(KdbxGroup g) {
    var n = g.entries.length;
    for (final c in childGroups(g)) {
      n += countIn(c);
    }
    return n;
  }

  /// 分组深度（根的直接子分组为 0）
  int depth(KdbxGroup g) => g.breadcrumbs.length - 2;

  String groupName(KdbxGroup g) =>
      g == root ? name : (g.name.get()?.trim().isNotEmpty == true ? g.name.get()! : '（未命名分组）');

  String groupPath(KdbxGroup g) => g.breadcrumbs
      .where((x) => x != root)
      .map((x) => x.name.get() ?? '')
      .join(' / ');

  List<KdbxEntry> search(String query, {KdbxGroup? inGroup}) {
    final base = inGroup == null
        ? entries
        : inGroup.getAllEntries().where((e) => !e.isHistoryEntry && !isHidden(e)).toList();
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
              if (e.parent != null) e.parent!.name.get() ?? '',
              for (final kv in e.visibleCustomFields.entries)
                if (!e.isProtected(kv.key)) kv.value,
            ].join('\n').toLowerCase();
            return q.split(RegExp(r'\s+')).every(hay.contains);
          }).toList();
    list.sort((a, b) => naturalCompare(a.title, b.title));
    return list;
  }

  KdbxEntry createEntry(KdbxGroup group) {
    final e = KdbxEntry.create(file, group);
    group.addEntry(e);
    return e;
  }

  KdbxGroup createGroup(String name, {KdbxGroup? parent, KdbxIcon? icon}) {
    final g = file.createGroup(parent: parent ?? root, name: name);
    if (icon != null) g.icon.set(icon);
    return g;
  }

  /// 删除条目：移入回收站；已在回收站中则永久删除
  void deleteEntry(KdbxEntry e) {
    if (inRecycleBin(e)) {
      file.deletePermanently(e);
    } else {
      KdbxFile.recycleBinName = '回收站';
      file.deleteEntry(e);
    }
  }

  /// 删除分组（连同其中的条目）：移入回收站；已在回收站中则永久删除
  void deleteGroup(KdbxGroup g) {
    if (g == root || isSpecialGroup(g)) {
      throw StateError('不能删除这个分组');
    }
    if (inRecycleBin(g)) {
      file.deletePermanently(g);
    } else {
      KdbxFile.recycleBinName = '回收站';
      file.deleteGroup(g);
    }
  }

  void moveEntry(KdbxEntry e, KdbxGroup to) {
    if (e.parent == to) return;
    file.move(e, to);
  }

  /// 能否把分组 g 移动到 to（不能移到自身或自己的子分组里）
  bool canMoveGroup(KdbxGroup g, KdbxGroup to) {
    if (g == root || isSpecialGroup(g)) return false;
    if (g.parent == to) return false;
    return !_under(to, g);
  }

  void moveGroup(KdbxGroup g, KdbxGroup to) {
    if (!canMoveGroup(g, to)) throw StateError('不能移动到这个位置');
    file.move(g, to);
  }

  /// 在同级分组中上移（-1）或下移（+1）
  bool shiftGroup(KdbxGroup g, int delta) {
    final parent = g.parent;
    if (parent == null) return false;
    final siblings = parent.groups;
    final i = siblings.indexOf(g);
    var j = i + delta;
    // 跳过回收站、模板等特殊分组
    while (j >= 0 && j < siblings.length && isSpecialGroup(siblings[j])) {
      j += delta;
    }
    if (j < 0 || j >= siblings.length) return false;
    parent.reorderGroup(g, j);
    return true;
  }

  /// 回收站中的直接内容
  List<KdbxGroup> get recycledGroups => recycleBin?.groups.toList() ?? const [];
  List<KdbxEntry> get recycledEntries {
    final list = recycleBin?.entries.toList() ?? <KdbxEntry>[];
    list.sort((a, b) => naturalCompare(a.title, b.title));
    return list;
  }

  /// 从回收站恢复到原来的分组（找不到则放回根目录）
  void restore(KdbxObject o) {
    final prevId = o.previousParentGroup.get();
    KdbxGroup target = root;
    if (prevId != null) {
      for (final g in root.getAllGroups()) {
        if (g.uuid == prevId && !inRecycleBin(g)) {
          target = g;
          break;
        }
      }
    }
    file.move(o, target);
  }

  void emptyRecycleBin() {
    final bin = recycleBin;
    if (bin == null) return;
    for (final g in bin.groups.toList()) {
      file.deletePermanently(g);
    }
    for (final e in bin.entries.toList()) {
      file.deletePermanently(e);
    }
  }

  KdbxEntry? findEntry(String uuid) {
    for (final e in entries) {
      if (e.uuid.uuid == uuid) return e;
    }
    return null;
  }

  void dispose() => file.dispose();
}

/// 自然排序：让 "2.xxx" 排在 "10.xxx" 前面，忽略大小写
int naturalCompare(String a, String b) {
  final ra = RegExp(r'(\d+)|(\D+)');
  final ta = ra.allMatches(a.toLowerCase()).map((m) => m.group(0)!).toList();
  final tb = ra.allMatches(b.toLowerCase()).map((m) => m.group(0)!).toList();
  for (var i = 0; i < ta.length && i < tb.length; i++) {
    final x = ta[i], y = tb[i];
    final nx = int.tryParse(x), ny = int.tryParse(y);
    final c = (nx != null && ny != null) ? nx.compareTo(ny) : x.compareTo(y);
    if (c != 0) return c;
  }
  return ta.length.compareTo(tb.length);
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

  /// 可见的自定义字段（排除标准字段与模板内部字段 _etm_*）
  Map<String, String> get visibleCustomFields {
    final m = <String, String>{};
    for (final e in stringEntries) {
      final k = e.key.key;
      if (!Fields.standard.contains(k) && !k.startsWith('_etm_')) {
        m[k] = e.value?.getText() ?? '';
      }
    }
    return m;
  }

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

  /// 过期时间（未设置过期则为 null）
  DateTime? get expiry =>
      times.expires.get() == true ? times.expiryTime.get()?.toLocal() : null;

  set expiry(DateTime? d) {
    if (d == null) {
      if (times.expires.get() == true) times.expires.set(false);
    } else {
      times.expires.set(true);
      times.expiryTime.set(d.toUtc());
    }
  }

  bool get isExpired {
    final e = expiry;
    return e != null && e.isBefore(DateTime.now());
  }
}
