import 'package:flutter/material.dart';
import 'package:kdbx/kdbx.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../core/password_generator.dart';
import '../core/totp.dart';
import '../core/vault.dart';
import 'generator_sheet.dart';
import 'save_helper.dart';
import 'widgets.dart';

/// 新建或编辑条目。entry 为 null 时新建。返回 true 表示有修改。
class EntryEditPage extends StatefulWidget {
  const EntryEditPage({super.key, this.entry, this.initialGroup});

  final KdbxEntry? entry;
  final KdbxGroup? initialGroup;

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
}

class _EntryEditPageState extends State<EntryEditPage> {
  final _title = TextEditingController();
  final _user = TextEditingController();
  final _pw = TextEditingController();
  final _url = TextEditingController();
  final _notes = TextEditingController();
  final _otp = TextEditingController();
  final List<_CustomField> _custom = [];
  KdbxGroup? _group;
  bool _obscure = true;
  bool _saving = false;
  String? _otpError;

  /// 这些字段由专门的控件处理，不在"其他字段"中显示
  static bool _isSpecial(String k) =>
      k == Fields.otp || k.startsWith('TimeOtp-') || k == 'TOTP Seed' || k == 'TOTP Settings';

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    final vault = context.read<AppState>().session!.vault;
    if (e != null) {
      _title.text = e.title;
      _user.text = e.userName;
      _pw.text = e.password;
      _url.text = e.url;
      _notes.text = e.notes;
      _group = e.parent;
      final f = e.allFields;
      _otp.text = f[Fields.otp] ?? f['TimeOtp-Secret-Base32'] ?? f['TOTP Seed'] ?? '';
      for (final kv in e.customFields.entries) {
        if (_isSpecial(kv.key)) continue;
        _custom.add(_CustomField(kv.key, kv.value, e.isProtected(kv.key)));
      }
    } else {
      _group = widget.initialGroup ?? vault.root;
      _pw.text = PasswordGenerator.generate(context.read<AppState>().settings.generator);
    }
    _pw.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    for (final c in [_title, _user, _pw, _url, _notes, _otp]) {
      c.dispose();
    }
    for (final c in _custom) {
      c.key.dispose();
      c.value.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final app = context.read<AppState>();
    final s = app.session!;
    final otpText = _otp.text.trim();
    if (otpText.isNotEmpty && TotpConfig.parse(otpText) == null) {
      setState(() => _otpError = '无法识别，请粘贴 otpauth:// 链接或 Base32 密钥');
      return;
    }
    final keys = <String>{};
    for (final c in _custom) {
      final k = c.key.text.trim();
      if (k.isEmpty) continue;
      if (Fields.standard.contains(k) || !keys.add(k)) {
        showSnack(context, '字段名"$k"重复或与标准字段冲突', error: true);
        return;
      }
    }

    final e = widget.entry ?? s.vault.createEntry(_group ?? s.vault.root);
    e.setStr(Fields.title, _title.text.trim());
    e.setStr(Fields.userName, _user.text.trim());
    e.setStr(Fields.password, _pw.text, protect: true);
    e.setStr(Fields.url, _url.text.trim());
    e.setStr(Fields.notes, _notes.text);

    // TOTP：统一存为 KeePassXC 风格的 otp 字段
    final f = e.allFields;
    final oldOtp = f[Fields.otp] ?? f['TimeOtp-Secret-Base32'] ?? f['TOTP Seed'] ?? '';
    if (otpText != oldOtp) {
      for (final k in f.keys.where(_isSpecial)) {
        e.removeString(KdbxKey(k));
      }
      if (otpText.isNotEmpty) {
        final uri = otpText.toLowerCase().startsWith('otpauth://')
            ? otpText
            : 'otpauth://totp/${Uri.encodeComponent(_title.text.trim().isEmpty ? 'PassVault' : _title.text.trim())}?secret=${otpText.replaceAll(' ', '').toUpperCase()}&period=30&digits=6';
        e.setStr(Fields.otp, uri, protect: true);
      }
    }

    // 自定义字段：删除已移除的，写入新的
    for (final k in e.customFields.keys.toList()) {
      if (_isSpecial(k)) continue;
      if (!keys.contains(k)) e.removeString(KdbxKey(k));
    }
    for (final c in _custom) {
      final k = c.key.text.trim();
      if (k.isEmpty) continue;
      final old = e.getString(KdbxKey(k));
      final protChanged = (old is ProtectedValue) != c.protect;
      if (old?.getText() != c.value.text || protChanged) {
        e.setString(
          KdbxKey(k),
          c.protect ? ProtectedValue.fromString(c.value.text) : PlainValue(c.value.text),
        );
      }
    }

    if (widget.entry != null && _group != null && e.parent != _group) {
      s.vault.moveEntry(e, _group!);
    }

    s.touch();
    setState(() => _saving = true);
    await saveSession(context, s);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final vault = context.read<AppState>().session!.vault;
    final groups = [vault.root, ...vault.groups];
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.entry == null ? '新建条目' : '编辑条目'),
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
              TextField(
                controller: _title,
                autofocus: widget.entry == null,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: '标题', prefixIcon: Icon(Icons.title)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _user,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                decoration: const InputDecoration(labelText: '用户名 / 邮箱 / 手机号', prefixIcon: Icon(Icons.person_outline)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _pw,
                obscureText: _obscure,
                autocorrect: false,
                enableSuggestions: false,
                style: const TextStyle(fontFamily: 'monospace', fontFamilyFallback: ['Consolas', 'Roboto Mono']),
                decoration: InputDecoration(
                  labelText: '密码',
                  prefixIcon: const Icon(Icons.password_rounded),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: () => setState(() => _obscure = !_obscure),
                        icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                      ),
                      IconButton(
                        tooltip: '生成密码',
                        onPressed: () async {
                          final pw = await showGenerator(context, forEntry: true);
                          if (pw != null) _pw.text = pw;
                        },
                        icon: const Icon(Icons.auto_awesome),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                child: StrengthBar(password: _pw.text),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _url,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: const InputDecoration(labelText: '网址', prefixIcon: Icon(Icons.link_rounded)),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<KdbxGroup>(
                initialValue: groups.contains(_group) ? _group : vault.root,
                isExpanded: true,
                decoration: const InputDecoration(labelText: '分组', prefixIcon: Icon(Icons.folder_outlined)),
                items: [
                  for (final g in groups)
                    DropdownMenuItem(
                      value: g,
                      child: Text(g == vault.root ? '（根目录）' : vault.groupPath(g),
                          overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (g) => setState(() => _group = g),
              ),
              const SizedBox(height: 12),
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
              const SizedBox(height: 12),
              TextField(
                controller: _notes,
                minLines: 3,
                maxLines: 10,
                decoration: const InputDecoration(labelText: '备注', alignLabelWithHint: true, prefixIcon: Icon(Icons.notes)),
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
                            obscureText: c.protect,
                            decoration: const InputDecoration(labelText: '值', isDense: true),
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
