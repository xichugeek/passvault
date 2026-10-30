import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../core/session.dart';
import '../core/vault.dart';
import '../core/vault_source.dart';
import '../platform/android_saf.dart';
import '../platform/quick_unlock.dart';
import 'widgets.dart';

/// 选择/新建密码库
class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.onPick});

  final void Function(VaultSource source) onPick;

  Future<void> _open(BuildContext context) async {
    VaultSource? s;
    try {
      if (Platform.isAndroid) {
        final r = await AndroidSaf.openDocument();
        if (r != null) {
          s = SafSource(uri: r['uri']!, name: r['name'] ?? 'vault.kdbx', provider: r['provider'] ?? '');
        }
      } else {
        // 显示所有文件：KeePass 密码库不一定带 .kdbx 后缀（例如 Keepass2Android 创建的文件）
        final r = await FilePicker.pickFile(
          dialogTitle: '打开 KeePass 密码库',
          type: FileType.any,
        );
        final path = r?.path;
        if (path != null) s = LocalFileSource(path);
      }
    } catch (e) {
      if (context.mounted) showSnack(context, '打开失败：$e', error: true);
    }
    if (s != null) onPick(s);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final recents = app.settings.recents;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 32, 20, 24),
              children: [
                Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [scheme.primary, scheme.tertiary]),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(Icons.shield_rounded, color: scheme.onPrimary, size: 28),
                    ),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('PassVault',
                            style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                        Text('KeePass 兼容 · Windows / Android 同步',
                            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                if (recents.isNotEmpty) ...[
                  Text('最近使用', style: text.titleSmall?.copyWith(color: scheme.primary)),
                  const SizedBox(height: 8),
                  for (final r in recents)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: scheme.primaryContainer,
                            child: Icon(Icons.folder_special_rounded,
                                color: scheme.onPrimaryContainer),
                          ),
                          title: Text(r.displayName),
                          subtitle: Text(r.locationHint,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          onTap: () => onPick(r),
                          trailing: PopupMenuButton<String>(
                            onSelected: (v) async {
                              if (v == 'remove') {
                                await QuickUnlock.disable(r.id);
                                await VaultSession.deleteCache(r);
                                await app.settings.removeRecent(r);
                              }
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'remove', child: Text('从列表移除')),
                            ],
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),
                ],
                FilledButton.icon(
                  onPressed: () => _open(context),
                  icon: const Icon(Icons.folder_open_rounded),
                  label: Text(Platform.isAndroid ? '打开密码库（可选 Google Drive）' : '打开密码库'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final s = await Navigator.push<VaultSession>(
                      context,
                      MaterialPageRoute(builder: (_) => const CreateVaultPage()),
                    );
                    if (s != null) app.setSession(s);
                  },
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('新建密码库'),
                ),
                const SizedBox(height: 28),
                Card(
                  color: scheme.secondaryContainer.withValues(alpha: 0.5),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.sync_rounded, color: scheme.secondary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            Platform.isAndroid
                                ? '同步提示：点"打开密码库"，在左上角菜单选择 Google Drive，找到你的密码库文件即可。修改会自动写回 Google Drive，电脑上的 PassVault 会读到同一个文件。'
                                : '同步提示：安装"Google Drive 电脑版"，打开同步文件夹（通常是 G:\\我的云端硬盘）里的密码库文件即可（有没有 .kdbx 后缀都可以），修改会自动同步到手机。',
                            style: text.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 新建密码库
class CreateVaultPage extends StatefulWidget {
  const CreateVaultPage({super.key});

  @override
  State<CreateVaultPage> createState() => _CreateVaultPageState();
}

class _CreateVaultPageState extends State<CreateVaultPage> {
  final _name = TextEditingController(text: '我的密码库');
  final _pw1 = TextEditingController();
  final _pw2 = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _pw1.dispose();
    _pw2.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_pw1.text.length < 8) {
      setState(() => _error = '主密码至少 8 位，建议使用一句容易记住的长句');
      return;
    }
    if (_pw1.text != _pw2.text) {
      setState(() => _error = '两次输入的主密码不一致');
      return;
    }
    final fileName = '${_name.text.trim().isEmpty ? 'passvault' : _name.text.trim()}.kdbx';
    VaultSource? source;
    if (Platform.isAndroid) {
      final r = await AndroidSaf.createDocument(fileName);
      if (r != null) {
        source = SafSource(uri: r['uri']!, name: r['name'] ?? fileName, provider: r['provider'] ?? '');
      }
    } else {
      final uri = await FilePicker.saveFile(
        dialogTitle: '保存新密码库（建议放在 Google Drive 同步文件夹）',
        fileName: fileName,
        bytes: Uint8List(0),
      );
      final path = uri != null && uri.scheme == 'file' ? uri.toFilePath() : null;
      if (path != null) {
        source = LocalFileSource(path.toLowerCase().endsWith('.kdbx') ? path : '$path.kdbx');
      }
    }
    if (source == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final s = await VaultSession.create(
        source,
        _name.text.trim().isEmpty ? '我的密码库' : _name.text.trim(),
        Vault.credentials(_pw1.text, null),
      );
      if (mounted) Navigator.pop(context, s);
    } catch (e) {
      setState(() => _error = '创建失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('新建密码库')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: '名称', prefixIcon: Icon(Icons.badge_outlined)),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _pw1,
                obscureText: _obscure,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: '主密码',
                  prefixIcon: const Icon(Icons.key_rounded),
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: StrengthBar(password: _pw1.text),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _pw2,
                obscureText: _obscure,
                decoration: const InputDecoration(labelText: '再次输入主密码', prefixIcon: Icon(Icons.key_rounded)),
              ),
              const SizedBox(height: 12),
              Text(
                '主密码无法找回，请务必牢记。文件使用 KeePass 标准格式（KDBX 4 + Argon2 + AES-256），也可以用 KeePassXC、Keepass2Android 打开。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : _create,
                child: _busy
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                    : const Text('选择保存位置并创建'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
