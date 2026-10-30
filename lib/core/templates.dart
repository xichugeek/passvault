import 'dart:typed_data';

import 'package:kdbx/kdbx.dart';

import 'vault.dart';

/// 模板字段类型（与 Keepass2Android / KeePass "KPEntryTemplates" 插件的 _etm_type_ 取值一致）
enum TFieldType {
  inline('Inline'),
  inlineUrl('Inline URL'),
  protectedInline('Protected Inline'),
  popout('Popout'),
  protectedPopout('Protected Popout'),
  richText('Rich Textbox'),
  date('Date'),
  time('Time'),
  dateTime('Date Time'),
  checkbox('Checkbox'),
  listbox('Listbox'),
  divider('Divider');

  const TFieldType(this.raw);
  final String raw;

  static TFieldType parse(String? s) {
    final v = (s ?? '').trim().toLowerCase();
    for (final t in values) {
      if (t.raw.toLowerCase() == v) return t;
    }
    if (v.startsWith('protected')) return TFieldType.protectedInline;
    return TFieldType.inline;
  }

  bool get isProtected => raw.startsWith('Protected');
  bool get isMultiline =>
      this == popout || this == protectedPopout || this == richText;
  bool get isDate => this == date || this == dateTime || this == time;
}

/// 模板里的一个字段
class TField {
  const TField(this.key, this.type, {String? label, this.options = const []})
      : label = label ?? key;

  /// 实际保存的字段名：标准字段（Title/UserName/Password/URL/Notes）、
  /// 特殊字段（@exp_date 过期时间、@tags 标签）或自定义字段名
  final String key;
  final String label;
  final TFieldType type;
  final List<String> options;

  bool get isStandard => Fields.standard.contains(key);
  bool get isExpiry => key == '@exp_date';
  bool get isTags => key == '@tags';
  bool get isSpecial => key.startsWith('@');

  /// 在界面上显示的名称
  String get displayLabel {
    switch (key) {
      case Fields.title:
        return '标题';
      case Fields.userName:
        return '用户名';
      case Fields.password:
        return '密码';
      case Fields.url:
        return '网址';
      case Fields.notes:
        return '备注';
      case '@exp_date':
        return '有效期至';
      case '@tags':
        return '标签';
      case '@override':
        return '覆盖网址';
    }
    return label;
  }
}

/// 一个条目模板
class EntryTemplate {
  EntryTemplate({
    required this.title,
    required this.icon,
    required this.fields,
    this.uuidHex,
    this.entry,
    this.builtinId,
  });

  final String title;
  final KdbxIcon icon;
  final List<TField> fields;

  /// 模板条目 UUID（十六进制，大写），Keepass2Android 用它关联条目
  final String? uuidHex;

  /// 库中的模板条目（内置模板尚未加入库时为 null）
  final KdbxEntry? entry;

  /// 内置模板标识
  final String? builtinId;

  Uint8List? get customIconData => entry?.customIcon?.data;
}

String uuidToHex(KdbxUuid u) =>
    u.toBytes().map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();

KdbxUuid uuidFromHex(String hex) {
  final h = hex.trim();
  final bytes = Uint8List(16);
  for (var i = 0; i < 16; i++) {
    bytes[i] = int.parse(h.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return KdbxUuid.fromBytes(bytes);
}

/// 内置模板定义（前 6 个与 Keepass2Android 自带模板使用相同 UUID，
/// 若库中已有这些模板会直接复用，不会重复添加）
class BuiltinTemplate {
  const BuiltinTemplate(this.id, this.uuidHex, this.title, this.icon, this.fields);

  final String id;
  final String uuidHex;
  final String title;
  final KdbxIcon icon;
  final List<TField> fields;
}

const builtinTemplates = <BuiltinTemplate>[
  BuiltinTemplate('notes', '10F8C25C26AE9B49A47FDA7CDACACEE2', '安全说明', KdbxIcon.Notepad, [
    TField(Fields.notes, TFieldType.popout),
  ]),
  BuiltinTemplate('email', '0B84EC3029E330478CD99B670942295B', '电子邮箱', KdbxIcon.EMail, [
    TField('电子邮箱', TFieldType.inline),
    TField(Fields.url, TFieldType.inline),
    TField(Fields.password, TFieldType.protectedInline),
  ]),
  BuiltinTemplate('membership', 'DD5C627BC66C28498FDEC70740D29168', '会员', KdbxIcon.UserKey, [
    TField('会员号', TFieldType.inline),
    TField(Fields.url, TFieldType.inline),
    TField('@exp_date', TFieldType.dateTime),
  ]),
  BuiltinTemplate('idcard', 'A7B525BD0CECC84EB9F0CEDC0B49B5B8', '身份卡', KdbxIcon.Identity, [
    TField('号码', TFieldType.inline),
    TField('姓名', TFieldType.inline),
    TField('签发地', TFieldType.inline),
    TField('签发日期', TFieldType.date),
    TField('@exp_date', TFieldType.dateTime),
  ]),
  BuiltinTemplate('wlan', '46B56A7E90407545B646E8DC488A5FA2', '无线局域网', KdbxIcon.IRCommunication, [
    TField('SSID', TFieldType.inline),
    TField(Fields.password, TFieldType.protectedInline),
  ]),
  BuiltinTemplate('creditcard', '49DD48DBFF149445B3392CE90EA75309', '信用卡', KdbxIcon.Homebanking, [
    TField('卡号', TFieldType.inline),
    TField('CVV', TFieldType.protectedInline),
    TField('PIN', TFieldType.protectedInline),
    TField('持卡人', TFieldType.inline),
    TField('@exp_date', TFieldType.dateTime),
  ]),
  // 以下为 PassVault 补充的常用模板
  BuiltinTemplate('bank', '5056A1B2C3D44E5F8A9B0C1D2E3F4051', '银行账户', KdbxIcon.Money, [
    TField('开户行', TFieldType.inline),
    TField('户名', TFieldType.inline),
    TField('账号', TFieldType.inline),
    TField(Fields.userName, TFieldType.inline),
    TField(Fields.password, TFieldType.protectedInline),
    TField('交易密码', TFieldType.protectedInline),
    TField(Fields.url, TFieldType.inline),
  ]),
  BuiltinTemplate('server', '5056A1B2C3D44E5F8A9B0C1D2E3F4052', '服务器', KdbxIcon.NetworkServer, [
    TField('主机地址', TFieldType.inline),
    TField('端口', TFieldType.inline),
    TField(Fields.userName, TFieldType.inline),
    TField(Fields.password, TFieldType.protectedInline),
    TField('私钥口令', TFieldType.protectedInline),
    TField(Fields.url, TFieldType.inline),
  ]),
  BuiltinTemplate('license', '5056A1B2C3D44E5F8A9B0C1D2E3F4053', '软件授权', KdbxIcon.Certificate, [
    TField('版本', TFieldType.inline),
    TField('授权码', TFieldType.protectedPopout),
    TField('注册邮箱', TFieldType.inline),
    TField('购买日期', TFieldType.date),
    TField(Fields.url, TFieldType.inline),
  ]),
  BuiltinTemplate('router', '5056A1B2C3D44E5F8A9B0C1D2E3F4054', '路由器', KdbxIcon.WorldSocket, [
    TField('管理地址', TFieldType.inline),
    TField(Fields.userName, TFieldType.inline),
    TField(Fields.password, TFieldType.protectedInline),
    TField('Wi-Fi 名称', TFieldType.inline),
    TField('Wi-Fi 密码', TFieldType.protectedInline),
  ]),
];

class Templates {
  Templates(this.vault);

  final Vault vault;

  static const _marker = '_etm_template';
  static const _ref = '_etm_template_uuid';

  /// 解析一个模板条目
  static EntryTemplate? parse(KdbxEntry e) {
    final f = e.allFields;
    if (!f.containsKey(_marker)) return null;
    final defs = <({int pos, TField field})>[];
    for (final k in f.keys) {
      if (!k.startsWith('_etm_title_')) continue;
      final key = k.substring('_etm_title_'.length);
      final type = TFieldType.parse(f['_etm_type_$key']);
      final pos = int.tryParse(f['_etm_position_$key'] ?? '') ?? 1 << 30;
      final opts = (f['_etm_options_$key'] ?? '')
          .split(RegExp(r'[,\n]'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      final label = f[k]!.trim().isEmpty ? key : f[k]!;
      defs.add((pos: pos, field: TField(key, type, label: label, options: opts)));
    }
    defs.sort((a, b) {
      final c = a.pos.compareTo(b.pos);
      return c != 0 ? c : a.field.key.compareTo(b.field.key);
    });
    return EntryTemplate(
      title: e.title.isEmpty ? '模板' : e.title,
      icon: e.icon.get() ?? KdbxIcon.Key,
      fields: [for (final d in defs) d.field],
      uuidHex: uuidToHex(e.uuid),
      entry: e,
    );
  }

  /// 库中已有的模板（模板分组里带 _etm_template 的条目，保持原有顺序）
  List<EntryTemplate> get existing {
    final g = vault.templatesGroup;
    if (g == null) return <EntryTemplate>[];
    return [
      for (final e in g.getAllEntries())
        if (!e.isHistoryEntry) ?parse(e),
    ];
  }

  /// 新建菜单中显示的全部模板：库里的模板 + 尚未加入库的内置模板
  List<EntryTemplate> get available {
    final list = [...existing];
    final have = {for (final t in list) t.uuidHex};
    for (final b in builtinTemplates) {
      if (have.contains(b.uuidHex)) continue;
      list.add(EntryTemplate(
        title: b.title,
        icon: b.icon,
        fields: b.fields,
        uuidHex: b.uuidHex,
        builtinId: b.id,
      ));
    }
    return list;
  }

  /// 条目所用的模板（没有则 null）
  EntryTemplate? templateOf(KdbxEntry e) {
    final hex = e.str(_ref).trim().toUpperCase();
    if (hex.isEmpty) return null;
    for (final t in existing) {
      if (t.uuidHex == hex) return t;
    }
    // 模板已被删除但内置定义还在
    for (final b in builtinTemplates) {
      if (b.uuidHex == hex) {
        return EntryTemplate(title: b.title, icon: b.icon, fields: b.fields, uuidHex: b.uuidHex, builtinId: b.id);
      }
    }
    return null;
  }

  /// 确保模板分组存在（与 Keepass2Android 一样记录在 EntryTemplatesGroup 中）
  KdbxGroup ensureTemplatesGroup() {
    final g = vault.templatesGroup;
    if (g != null) return g;
    final created = vault.createGroup('模板', icon: KdbxIcon.Folder);
    vault.file.body.meta.entryTemplatesGroup.set(created.uuid);
    return created;
  }

  /// 把内置模板写入库中（Keepass2Android 也能识别），返回库中的模板
  EntryTemplate materialize(EntryTemplate t) {
    if (t.entry != null) return t;
    final group = ensureTemplatesGroup();
    final e = KdbxEntry.create(vault.file, group);
    // 使用固定 UUID，与 Keepass2Android 自带模板保持一致
    if (t.uuidHex != null) {
      e.overrideUuid(uuidFromHex(t.uuidHex!));
    }
    group.addEntry(e);
    e.setStr(Fields.title, t.title);
    e.icon.set(t.icon);
    e.setStr(_marker, '1');
    for (var i = 0; i < t.fields.length; i++) {
      final f = t.fields[i];
      e.setStr('_etm_position_${f.key}', '$i');
      e.setStr('_etm_title_${f.key}', f.label);
      e.setStr('_etm_type_${f.key}', f.type.raw);
      if (f.options.isNotEmpty) e.setStr('_etm_options_${f.key}', f.options.join(','));
    }
    return parse(e)!;
  }

  /// 用模板新建条目（字段值为空，之后在编辑页面填写）
  KdbxEntry createFrom(EntryTemplate template, KdbxGroup group) {
    final t = materialize(template);
    final e = vault.createEntry(group);
    e.setStr(_ref, t.uuidHex!);
    e.icon.set(t.icon);
    final ci = t.entry?.customIcon;
    if (ci != null) e.customIcon = ci;
    return e;
  }
}

/// 列表中条目的副标题：用户名 → 网址域名 → 模板中第一个非保密字段 → 模板名称
String entrySubtitle(Templates t, KdbxEntry e) {
  if (e.userName.isNotEmpty) return e.userName;
  final url = e.url.trim();
  if (url.isNotEmpty) {
    final u = Uri.tryParse(url.contains('://') ? url : 'https://$url');
    return u?.host.isNotEmpty == true ? u!.host : url;
  }
  final tpl = t.templateOf(e);
  if (tpl != null) {
    for (final f in tpl.fields) {
      if (f.isStandard || f.isSpecial || f.type.isProtected || f.type == TFieldType.divider) continue;
      final v = e.str(f.key).trim();
      if (v.isNotEmpty) return v;
    }
    return tpl.title;
  }
  return '';
}
