import 'package:flutter/material.dart';
import 'package:kdbx/kdbx.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../core/password_generator.dart';
import '../core/templates.dart';
import '../core/totp.dart';
import '../core/vault.dart';
import 'generator_sheet.dart';
import 'kp_icons.dart';
import 'save_helper.dart';
import 'widgets.dart';

/// 新建或编辑条目。entry 为 null 时新建（可指定模板）。保存后返回该条目。
class EntryEditPage extends StatefulWidget {
  const EntryEditPage({super.key, this.entry, this.initialGroup, this.template});

  final KdbxEntry? entry;
  final KdbxGroup? initialGroup;
  final EntryTemplate? template;

  @override
  State<EntryEditPage> createState() => _EntryEditPageState();
}

class _CustomField {
  _CustomField(String k, String v, this.protect)
      : key = TextEditingController(text: k),
        value = TextEditingController(text: v);
  final TextEditingController key;
  final TextEditingController value;
  bool protect;
  bool obscure = true;
}

String fmtDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class _EntryEditPageState extends State<EntryEditPage> {
  final _title = TextEditingController();
  final _otp = TextEditingController();
  final Map<String, TextEditingController> _ctl = {};
  final Map<String, bool> _checks = {};
  final Set<String> _revealed = {};
  final List<_CustomField> _custom = [];
  EntryTemplate? _tpl;
  KdbxGroup? _group;
  IconChoice? _icon;
  DateTime? _expiry;
  bool _saving = false;
  String? _otpError;

  late final Vault _vault;

  /// 由专门控件处理、不在"其他字段"里显示的字段
  static bool _isOtpField(String k) =>
      k == Fields.otp || k.startsWith('TimeOtp-') || k == 'TOTP Seed' || k == 'TOTP Settings';

  /// 在编辑页上显示的标准字段
  List<String> get _standardKeys {
    const all = [Fields.userName, Fields.password, Fields.url, Fields.notes];
    final t = _tpl;
    if (t == null) return all;
    final inTpl = {for (final f in t.fields) f.key};
    // 模板模式：只显示模板里没有、但已有内容的标准字段
    return [
      for (final k in all)
        if (!inTpl.contains(k) && (widget.entry?.str(k).isNotEmpty ?? false)) k,
    ];
  }

  Set<String> get _templateKeys => {for (final f in _tpl?.fields ?? const <TField>[]) f.key};

  TextEditingController _c(String key) => _ctl.putIfAbsent(key, () {
        final c = TextEditingController(text: widget.entry?.str(key) ?? '');
        if (key == Fields.password) c.addListener(() => setState(() {}));
        return c;
      });

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    _vault = app.session!.vault;
    final e = widget.entry;
    _tpl = widget.template ?? (e == null ? null : Templates(_vault).templateOf(e));
    if (e != null) {
      _title.text = e.title;
      _group = e.parent;
      _expiry = e.expiry;
      final f = e.allFields;
      _otp.text = f[Fields.otp] ?? f['TimeOtp-Secret-Base32'] ?? f['TOTP Seed'] ?? '';
      final tk = _templateKeys;
      for (final kv in e.visibleCustomFields.entries) {
        if (_isOtpField(kv.key) || tk.contains(kv.key)) continue;
        _custom.add(_CustomField(kv.key, kv.value, e.isProtected(kv.key)));
      }
    } else {
      _group = widget.initialGroup ?? _vault.root;
      // 新条目自动生成一个强密码
      final needsPw = _tpl == null || _templateKeys.contains(Fields.password);
      if (needsPw) _c(Fields.password).text = PasswordGenerator.generate(app.settings.generator);
    }
    for (final f in _tpl?.fields ?? const <TField>[]) {
      if (f.type == TFieldType.checkbox) {
        _checks[f.key] = (e?.str(f.key) ?? '').toLowerCase() == 'true';
      }
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _otp.dispose();
    for (final c in _ctl.values) {
      c.dispose();
    }
    for (final c in _custom) {
      c.key.dispose();
      c.value.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final s = context.read<AppState>().session!;
    final otpText = _otp.text.trim();
    if (otpText.isNotEmpty && TotpConfig.parse(otpText) == null) {
      setState(() => _otpError = '无法识别，请粘贴 otpauth:// 链接或 Base32 密钥');
      return;
    }
    final tk = _templateKeys;
    final keys = <String>{};
    for (final c in _custom) {
      final k = c.key.text.trim();
      if (k.isEmpty) continue;
      if (Fields.standard.contains(k) || tk.contains(k) || k.startsWith('_etm_') || !keys.add(k)) {
        showSnack(context, '字段名"$k"重复或与已有字段冲突', error: true);
        return;
      }
    }

    final group = _group ?? _vault.root;
    final KdbxEntry e;
    if (widget.entry != null) {
      e = widget.entry!;
    } else if (_tpl != null) {
      e = Templates(_vault).createFrom(_tpl!, group);
    } else {
      e = _vault.createEntry(group);
    }

    e.setStr(Fields.title, _title.text.trim());

    // 模板字段
    for (final f in _tpl?.fields ?? const <TField>[]) {
      switch (f.type) {
        case TFieldType.divider:
          continue;
        case TFieldType.checkbox:
          e.setStr(f.key, (_checks[f.key] ?? false) ? 'true' : 'false');
          continue;
        default:
      }
      if (f.isExpiry) {
        e.expiry = _expiry;
      } else if (f.isTags) {
        final v = _c(f.key).text.trim();
        if ((e.tags.get() ?? '') != v) e.tags.set(v);
      } else if (f.isSpecial || f.key == Fields.title) {
        continue;
      } else {
        final v = _c(f.key).text;
        e.setStr(f.key, f.isStandard && f.key != Fields.notes ? v.trim() : v,
            protect: f.type.isProtected || f.key == Fields.password);
      }
    }

    // 标准字段
    for (final k in _standardKeys) {
      final v = _c(k).text;
      e.setStr(k, k == Fields.notes || k == Fields.password ? v : v.trim(), protect: k == Fields.password);
    }

    // 不在模板中的过期时间
    if (!tk.contains('@exp_date')) e.expiry = _expiry;

    // TOTP：统一存为 KeePassXC 风格的 otp 字段
    final f = e.allFields;
    final oldOtp = f[Fields.otp] ?? f['TimeOtp-Secret-Base32'] ?? f['TOTP Seed'] ?? '';
    if (otpText != oldOtp) {
      for (final k in f.keys.where(_isOtpField)) {
        e.removeString(KdbxKey(k));
      }
      if (otpText.isNotEmpty) {
        final label = Uri.encodeComponent(_title.text.trim().isEmpty ? 'PassVault' : _title.text.trim());
        final uri = otpText.toLowerCase().startsWith('otpauth://')
            ? otpText
            : 'otpauth://totp/$label?secret=${otpText.replaceAll(' ', '').toUpperCase()}&period=30&digits=6';
        e.setStr(Fields.otp, uri, protect: true);
      }
    }

    // 其他字段：删除已移除的，写入新的
    for (final k in e.visibleCustomFields.keys.toList()) {
      if (_isOtpField(k) || tk.contains(k)) continue;
      if (!keys.contains(k)) e.removeString(KdbxKey(k));
    }
    for (final c in _custom) {
      final k = c.key.text.trim();
      if (k.isEmpty) continue;
      final old = e.getString(KdbxKey(k));
      final protChanged = (old is ProtectedValue) != c.protect;
      if (old?.getText() != c.value.text || protChanged) {
        e.setString(KdbxKey(k), c.protect ? ProtectedValue.fromString(c.value.text) : PlainValue(c.value.text));
      }
    }

    _icon?.applyTo(e);

    if (widget.entry != null && _group != null && e.parent != _group) {
      _vault.moveEntry(e, _group!);
    }

    s.touch();
    setState(() => _saving = true);
    await saveSession(context, s);
    if (mounted) Navigator.pop(context, e);
  }

  Future<void> _pickDate(TextEditingController c, TFieldType type) async {
    final now = DateTime.now();
    if (type == TFieldType.time) {
      final t = await showTimePicker(context: context, initialTime: TimeOfDay.now());
      if (t != null) {
        c.text = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
      }
      return;
    }
    final initial = DateTime.tryParse(c.text.trim()) ?? now;
    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: DateTime(2200),
    );
    if (d != null) c.text = fmtDate(d);
  }

  Future<void> _pickExpiry() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _expiry ?? DateTime.now().add(const Duration(days: 365)),
      firstDate: DateTime(1990),
      lastDate: DateTime(2200),
      helpText: '有效期至',
    );
    if (d != null) setState(() => _expiry = DateTime(d.year, d.month, d.day, 23, 59));
  }

  Widget _passwordField(String key, String label) {
    final c = _c(key);
    final shown = _revealed.contains(key);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: c,
          obscureText: !shown,
          autocorrect: false,
          enableSuggestions: false,
          style: const TextStyle(fontFamily: 'monospace', fontFamilyFallback: ['Consolas', 'Roboto Mono']),
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: const Icon(Icons.password_rounded),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: () => setState(() => shown ? _revealed.remove(key) : _revealed.add(key)),
                  icon: Icon(shown ? Icons.visibility_off : Icons.visibility),
                ),
                IconButton(
                  tooltip: '生成密码',
                  onPressed: () async {
                    final pw = await showGenerator(context, forEntry: true);
                    if (pw != null) c.text = pw;
                  },
                  icon: const Icon(Icons.auto_awesome),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
          child: StrengthBar(password: c.text),
        ),
      ],
    );
  }

  IconData _iconForKey(String key) {
    switch (key) {
      case Fields.userName:
        return Icons.person_outline;
      case Fields.url:
        return Icons.link_rounded;
      case Fields.notes:
        return Icons.notes;
    }
    return Icons.short_text_rounded;
  }

  /// 根据模板字段类型生成编辑控件
  Widget _templateField(TField f) {
    switch (f.type) {
      case TFieldType.divider:
        return Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
          child: Text(f.displayLabel,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
        );
      case TFieldType.checkbox:
        return Card(
          child: SwitchListTile(
            title: Text(f.displayLabel),
            value: _checks[f.key] ?? false,
            onChanged: (v) => setState(() => _checks[f.key] = v),
          ),
        );
      case TFieldType.listbox:
        final c = _c(f.key);
        final opts = [...f.options];
        if (c.text.isNotEmpty && !opts.contains(c.text)) opts.insert(0, c.text);
        return DropdownButtonFormField<String>(
          initialValue: c.text.isEmpty ? null : c.text,
          isExpanded: true,
          decoration: InputDecoration(labelText: f.displayLabel, prefixIcon: const Icon(Icons.list_rounded)),
          items: [for (final o in opts) DropdownMenuItem(value: o, child: Text(o))],
          onChanged: (v) => setState(() => c.text = v ?? ''),
        );
      default:
    }
    if (f.isExpiry) return _expiryTile(f.displayLabel);
    if (f.key == Fields.password) return _passwordField(f.key, f.displayLabel);
    final c = _c(f.key);
    if (f.type.isProtected) {
      final shown = _revealed.contains(f.key);
      return TextField(
        controller: c,
        obscureText: !shown && !f.type.isMultiline,
        minLines: f.type.isMultiline && shown ? 2 : 1,
        maxLines: f.type.isMultiline && shown ? 6 : 1,
        autocorrect: false,
        enableSuggestions: false,
        decoration: InputDecoration(
          labelText: f.displayLabel,
          prefixIcon: const Icon(Icons.lock_outline),
          suffixIcon: IconButton(
            onPressed: () => setState(() => shown ? _revealed.remove(f.key) : _revealed.add(f.key)),
            icon: Icon(shown ? Icons.visibility_off : Icons.visibility),
          ),
        ),
      );
    }
    if (f.type.isDate) {
      return TextField(
        controller: c,
        decoration: InputDecoration(
          labelText: f.displayLabel,
          hintText: f.type == TFieldType.time ? 'HH:mm' : 'yyyy-MM-dd',
          prefixIcon: const Icon(Icons.event_outlined),
          suffixIcon: IconButton(
            icon: const Icon(Icons.calendar_month_outlined),
            onPressed: () => _pickDate(c, f.type),
          ),
        ),
      );
    }
    final isUrl = f.key == Fields.url || f.type == TFieldType.inlineUrl;
    final multi = f.type.isMultiline || f.key == Fields.notes;
    return TextField(
      controller: c,
      keyboardType: isUrl ? TextInputType.url : (multi ? TextInputType.multiline : TextInputType.text),
      autocorrect: false,
      minLines: multi ? 3 : 1,
      maxLines: multi ? 12 : 1,
      decoration: InputDecoration(
        labelText: f.displayLabel,
        alignLabelWithHint: multi,
        prefixIcon: Icon(isUrl ? Icons.link_rounded : _iconForKey(f.key)),
      ),
    );
  }

  Widget _expiryTile(String label) {
    final scheme = Theme.of(context).colorScheme;
    final expired = _expiry != null && _expiry!.isBefore(DateTime.now());
    return Card(
      child: ListTile(
        leading: Icon(Icons.event_available_outlined, color: expired ? scheme.error : null),
        title: Text(label),
        subtitle: Text(
          _expiry == null ? '不过期' : '${fmtDate(_expiry!)}${expired ? '（已过期）' : ''}',
          style: TextStyle(color: expired ? scheme.error : null),
        ),
        onTap: _pickExpiry,
        trailing: _expiry == null
            ? const Icon(Icons.chevron_right)
            : IconButton(
                tooltip: '清除',
                icon: const Icon(Icons.close),
                onPressed: () => setState(() => _expiry = null),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final groups = [_vault.root, ..._vault.groups];
    final tpl = _tpl;
    final titleText = widget.entry == null ? (tpl == null ? '新建条目' : '新建${tpl.title}') : '编辑条目';
    final previewIcon = _icon != null
        ? KpIcon(icon: _icon!.icon, custom: _icon!.custom, size: 52)
        : widget.entry != null
            ? KpIcon.of(widget.entry!, size: 52)
            : KpIcon(icon: tpl?.icon ?? KdbxIcon.Key, custom: tpl?.entry?.customIcon, size: 52);
    const gap = SizedBox(height: 12);

    return Scaffold(
      appBar: AppBar(
        title: Text(titleText),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(72, 40)),
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('保存'),
            ),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Tooltip(
                    message: '更换图标',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () async {
                        final c = await pickIcon(context, _vault.file, current: widget.entry);
                        if (c != null) setState(() => _icon = c);
                      },
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          previewIcon,
                          Positioned(
                            right: -4,
                            bottom: -4,
                            child: CircleAvatar(
                              radius: 11,
                              backgroundColor: Theme.of(context).colorScheme.primary,
                              child: Icon(Icons.edit, size: 12, color: Theme.of(context).colorScheme.onPrimary),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: TextField(
                      controller: _title,
                      autofocus: widget.entry == null,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(labelText: '标题', hintText: tpl?.title),
                    ),
                  ),
                ],
              ),
              gap,
              if (tpl != null)
                for (final f in tpl.fields)
                  if (f.key != Fields.title) ...[_templateField(f), gap],
              for (final k in _standardKeys) ...[
                if (k == Fields.password)
                  _passwordField(k, '密码')
                else
                  _templateField(TField(k, k == Fields.notes ? TFieldType.popout : TFieldType.inline)),
                gap,
              ],
              DropdownButtonFormField<KdbxGroup>(
                initialValue: groups.contains(_group) ? _group : _vault.root,
                isExpanded: true,
                decoration: const InputDecoration(labelText: '分组', prefixIcon: Icon(Icons.folder_outlined)),
                items: [
                  for (final g in groups)
                    DropdownMenuItem(
                      value: g,
                      child: Padding(
                        padding: EdgeInsets.only(left: g == _vault.root ? 0 : (_vault.depth(g) + 1) * 14.0),
                        child: Row(
                          children: [
                            KpIcon.of(g, size: 22),
                            const SizedBox(width: 10),
                            Expanded(child: Text(_vault.groupName(g), overflow: TextOverflow.ellipsis)),
                          ],
                        ),
                      ),
                    ),
                ],
                selectedItemBuilder: (_) => [
                  for (final g in groups)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(g == _vault.root ? _vault.name : _vault.groupPath(g),
                          overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (g) => setState(() => _group = g),
              ),
              gap,
              if (!_templateKeys.contains('@exp_date')) ...[_expiryTile('有效期至'), gap],
              TextField(
                controller: _otp,
                autocorrect: false,
                onChanged: (_) => setState(() => _otpError = null),
                decoration: InputDecoration(
                  labelText: '两步验证密钥（可选）',
                  helperText: '粘贴网站提供的 otpauth:// 链接或密钥，即可显示动态验证码',
                  errorText: _otpError,
                  prefixIcon: const Icon(Icons.timer_outlined),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Text('其他字段', style: Theme.of(context).textTheme.titleSmall),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => setState(() => _custom.add(_CustomField('', '', false))),
                    icon: const Icon(Icons.add),
                    label: const Text('添加字段'),
                  ),
                ],
              ),
              for (final c in _custom)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: c.key,
                                  decoration: const InputDecoration(labelText: '字段名', isDense: true),
                                ),
                              ),
                              IconButton(
                                tooltip: c.protect ? '受保护（隐藏显示）' : '普通',
                                onPressed: () => setState(() => c.protect = !c.protect),
                                icon: Icon(c.protect ? Icons.lock : Icons.lock_open),
                              ),
                              IconButton(
                                tooltip: '删除字段',
                                onPressed: () => setState(() => _custom.remove(c)),
                                icon: const Icon(Icons.close),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: c.value,
                            obscureText: c.protect && c.obscure,
                            decoration: InputDecoration(
                              labelText: '值',
                              isDense: true,
                              suffixIcon: c.protect
                                  ? IconButton(
                                      icon: Icon(c.obscure ? Icons.visibility : Icons.visibility_off),
                                      onPressed: () => setState(() => c.obscure = !c.obscure),
                                    )
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
