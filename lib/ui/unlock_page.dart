import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:kdbx/kdbx.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../core/session.dart';
import '../core/settings.dart';
import '../core/vault.dart';
import '../core/vault_source.dart';
import '../platform/android_saf.dart';
import '../platform/quick_unlock.dart';
import 'widgets.dart';

/// 解锁界面（主程序与自动填充共用）
class UnlockView extends StatefulWidget {
  const UnlockView({
    super.key,
    required this.source,
    required this.settings,
    required this.onUnlocked,
    this.onSwitchVault,
    this.subtitle,
    this.autoBiometric = true,
  });

  final VaultSource source;
  final Settings settings;
  final void Function(VaultSession session) onUnlocked;
  final VoidCallback? onSwitchVault;
  final String? subtitle;
  final bool autoBiometric;

  @override
  State<UnlockView> createState() => _UnlockViewState();
}

class _UnlockViewState extends State<UnlockView> {
  final _pw = TextEditingController();
  final _focus = FocusNode();
  bool _obscure = true;
  bool _busy = false;
  String? _error;
  bool _quickEnabled = false;
  bool _quickAvailable = false;
  String? _keyFile;

  @override
  void initState() {
    super.initState();
    _keyFile = widget.settings.keyFileFor(widget.source.id);
    _initQuick();
  }

  Future<void> _initQuick() async {
    final available = await QuickUnlock.isAvailable();
    final enabled = available && await QuickUnlock.isEnabled(widget.source.id);
    if (!mounted) return;
    setState(() {
      _quickAvailable = available;
      _quickEnabled = enabled;
    });
    if (enabled && widget.autoBiometric) {
      _unlockQuick();
    } else {
      _focus.requestFocus();
    }
  }

  @override
  void dispose() {
    _pw.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _unlockQuick() async {
    if (_busy) return;
    try {
      final hash = await QuickUnlock.unlock(widget.source.id,
          title: '解锁 ${widget.source.displayName}');
      if (hash == null) {
        _focus.requestFocus();
        return;
      }
      await _open(Credentials.fromHash(hash), fromQuick: true);
    } on QuickUnlockInvalidated catch (e) {
      setState(() {
        _quickEnabled = false;
        _error = e.toString();
      });
    } catch (e) {
      setState(() => _error = '快速解锁失败：$e');
    }
  }

  Future<void> _unlockPassword() async {
    if (_busy) return;
    if (_pw.text.isEmpty && _keyFile == null) {
      setState(() => _error = '请输入主密码');
      return;
    }
    Uint8List? kf;
    if (_keyFile != null) {
      try {
        kf = await readKeyFile(_keyFile!);
      } catch (e) {
        setState(() => _error = '无法读取密钥文件：$e');
        return;
      }
    }
    await _open(Vault.credentials(_pw.text, kf));
  }

  Future<void> _open(Credentials c, {bool fromQuick = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final session = await VaultSession.open(widget.source, c);
      if (!mounted) return;
      if (!fromQuick && _quickAvailable && !_quickEnabled) {
        await _offerQuickUnlock(session);
      }
      if (!mounted) return;
      widget.onUnlocked(session);
    } on KdbxInvalidKeyException {
      if (fromQuick) {
        // 主密码已在别处修改，旧的快速解锁数据作废
        await QuickUnlock.disable(widget.source.id);
        _quickEnabled = false;
        setState(() => _error = '主密码似乎已修改，请输入新的主密码');
      } else {
        setState(() => _error = '主密码或密钥文件不正确');
      }
      _focus.requestFocus();
    } on FileSystemException catch (e) {
      setState(() => _error = '找不到文件：${e.path ?? ''}\n${e.osError?.message ?? e.message}');
    } catch (e) {
      setState(() => _error = '打开失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _offerQuickUnlock(VaultSession session) async {
    final yes = await confirm(
      context,
      '开启${QuickUnlock.methodName}解锁？',
      '以后打开密码库和自动填充时，用${QuickUnlock.methodName}即可解锁，不用再输入主密码。',
      ok: '开启',
    );
    if (!yes) return;
    try {
      await QuickUnlock.enable(widget.source.id, session.compositeHash);
    } catch (e) {
      if (mounted) showSnack(context, '开启失败：$e', error: true);
    }
  }

  Future<void> _pickKeyFile() async {
    String? loc;
    if (Platform.isAndroid) {
      final r = await AndroidSaf.openDocument();
      loc = r?['uri'];
    } else {
      final r = await FilePicker.pickFile(dialogTitle: '选择密钥文件');
      loc = r?.path;
    }
    if (loc == null) return;
    await widget.settings.setKeyFileFor(widget.source.id, loc);
    setState(() => _keyFile = loc);
  }

  String _keyFileName(String loc) {
    if (loc.startsWith('content://')) {
      final last = Uri.decodeComponent(loc.split('/').last);
      return last.split(':').last.split('/').last;
    }
    return p.basename(loc);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [scheme.primary, scheme.tertiary],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(26),
                    boxShadow: [
                      BoxShadow(
                        color: scheme.primary.withValues(alpha: 0.35),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Icon(Icons.lock_rounded, size: 40, color: scheme.onPrimary),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                widget.source.displayName,
                textAlign: TextAlign.center,
                style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                widget.subtitle ?? widget.source.locationHint,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _pw,
                focusNode: _focus,
                obscureText: _obscure,
                enabled: !_busy,
                autofillHints: const [AutofillHints.password],
                enableSuggestions: false,
                autocorrect: false,
                textInputAction: TextInputAction.go,
                onSubmitted: (_) => _unlockPassword(),
                decoration: InputDecoration(
                  hintText: '主密码',
                  prefixIcon: const Icon(Icons.key_rounded),
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: _keyFile == null
                    ? TextButton.icon(
                        onPressed: _busy ? null : _pickKeyFile,
                        icon: const Icon(Icons.vpn_key_outlined, size: 18),
                        label: const Text('使用密钥文件'),
                      )
                    : InputChip(
                        avatar: const Icon(Icons.vpn_key, size: 18),
                        label: Text(_keyFileName(_keyFile!)),
                        onPressed: _pickKeyFile,
                        onDeleted: () async {
                          await widget.settings.setKeyFileFor(widget.source.id, null);
                          setState(() => _keyFile = null);
                        },
                      ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                child: _error == null
                    ? const SizedBox(height: 8)
                    : Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(_error!,
                            style: TextStyle(color: scheme.error),
                            textAlign: TextAlign.center),
                      ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: _busy ? null : _unlockPassword,
                      child: _busy
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2.5),
                            )
                          : const Text('解锁'),
                    ),
                  ),
                  if (_quickEnabled) ...[
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 56,
                      height: 52,
                      child: IconButton.filledTonal(
                        tooltip: QuickUnlock.methodName,
                        onPressed: _busy ? null : _unlockQuick,
                        icon: Icon(Platform.isWindows
                            ? Icons.face_retouching_natural
                            : Icons.fingerprint),
                      ),
                    ),
                  ],
                ],
              ),
              if (widget.onSwitchVault != null) ...[
                const SizedBox(height: 16),
                TextButton.icon(
                  onPressed: _busy ? null : widget.onSwitchVault,
                  icon: const Icon(Icons.swap_horiz),
                  label: const Text('切换或新建密码库'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 主程序的解锁页面
class UnlockPage extends StatelessWidget {
  const UnlockPage({super.key, required this.source, this.onSwitchVault});

  final VaultSource source;
  final VoidCallback? onSwitchVault;

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    return Scaffold(
      body: SafeArea(
        child: UnlockView(
          key: ValueKey(source.id),
          source: source,
          settings: app.settings,
          onUnlocked: app.setSession,
          onSwitchVault: onSwitchVault,
        ),
      ),
    );
  }
}
