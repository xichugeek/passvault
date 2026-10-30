import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../core/session.dart';
import '../core/vault.dart';
import '../platform/quick_unlock.dart';
import '../platform/system_bridge.dart';
import 'save_helper.dart';
import 'theme.dart';
import 'widgets.dart';
import 'sheet.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> with WidgetsBindingObserver {
  bool? _quickAvailable;
  bool _quickEnabled = false;
  bool _autofillSupported = false;
  bool _autofillEnabled = false;
  String _version = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 从系统设置返回后刷新自动填充状态
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final s = context.read<AppState>().session;
    final qa = await QuickUnlock.isAvailable();
    final qe = s != null && await QuickUnlock.isEnabled(s.source.id);
    final as = await SystemBridge.isAutofillSupported();
    final ae = await SystemBridge.isAutofillEnabled();
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() {
      _quickAvailable = qa;
      _quickEnabled = qe;
      _autofillSupported = as;
      _autofillEnabled = ae;
      _version = '${info.version}+${info.buildNumber}';
    });
  }

  Future<void> _changeMasterPassword() async {
    final app = context.read<AppState>();
    final s = app.session!;
    final p1 = TextEditingController();
    final p2 = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: const Text('修改主密码'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: p1,
                obscureText: true,
                onChanged: (_) => setD(() {}),
                decoration: const InputDecoration(labelText: '新主密码'),
              ),
              const SizedBox(height: 8),
              StrengthBar(password: p1.text),
              const SizedBox(height: 8),
              TextField(controller: p2, obscureText: true, decoration: const InputDecoration(labelText: '再次输入')),
              const SizedBox(height: 12),
              const Text('修改后，其他设备需要用新密码重新解锁。密钥文件设置保持不变。',
                  style: TextStyle(fontSize: 12)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
              onPressed: p1.text.length >= 8 && p1.text == p2.text ? () => Navigator.pop(c, true) : null,
              child: const Text('修改'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final kfLoc = app.settings.keyFileFor(s.source.id);
      final kf = kfLoc == null ? null : await readKeyFile(kfLoc);
      await s.changeMasterKey(Vault.credentials(p1.text, kf));
      await QuickUnlock.disable(s.source.id);
      if (mounted) {
        showSnack(context, '主密码已修改');
        _refresh();
      }
    } catch (e) {
      if (mounted) showSnack(context, '修改失败：$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final st = app.settings;
    final s = app.session;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: pagePadding(context, top: 0),
            children: [
              SectionCard(title: '外观', children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(value: ThemeMode.system, label: Text('跟随系统'), icon: Icon(Icons.brightness_auto)),
                      ButtonSegment(value: ThemeMode.light, label: Text('浅色'), icon: Icon(Icons.light_mode)),
                      ButtonSegment(value: ThemeMode.dark, label: Text('深色'), icon: Icon(Icons.dark_mode)),
                    ],
                    selected: {st.themeMode},
                    onSelectionChanged: (v) => st.update((x) => x.themeMode = v.first),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final c in seedChoices.entries)
                        Tooltip(
                          message: c.value,
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () => st.update((x) => x.seedColor = c.key),
                            child: CircleAvatar(
                              radius: 18,
                              backgroundColor: Color(c.key),
                              child: st.seedColor == c.key
                                  ? const Icon(Icons.check, color: Colors.white, size: 18)
                                  : null,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ]),
              const SizedBox(height: 16),
              SectionCard(title: '安全', children: [
                if (s != null && _quickAvailable == true)
                  SwitchListTile(
                    secondary: Icon(Platform.isWindows ? Icons.face_retouching_natural : Icons.fingerprint),
                    title: Text('${QuickUnlock.methodName}解锁'),
                    subtitle: Text('用于"${s.source.displayName}"'),
                    value: _quickEnabled,
                    onChanged: (v) async {
                      if (v) {
                        try {
                          final ok = await QuickUnlock.enable(s.source.id, s.compositeHash);
                          if (!ok && context.mounted) showSnack(context, '未开启');
                        } catch (e) {
                          if (context.mounted) showSnack(context, '开启失败：$e', error: true);
                        }
                      } else {
                        await QuickUnlock.disable(s.source.id);
                      }
                      _refresh();
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.timer_outlined),
                  title: const Text('无操作自动锁定'),
                  trailing: DropdownButton<int>(
                    value: st.autoLockMinutes,
                    underline: const SizedBox.shrink(),
                    items: const [
                      DropdownMenuItem(value: 1, child: Text('1 分钟')),
                      DropdownMenuItem(value: 5, child: Text('5 分钟')),
                      DropdownMenuItem(value: 15, child: Text('15 分钟')),
                      DropdownMenuItem(value: 30, child: Text('30 分钟')),
                      DropdownMenuItem(value: 60, child: Text('1 小时')),
                      DropdownMenuItem(value: 0, child: Text('从不')),
                    ],
                    onChanged: (v) => st.update((x) => x.autoLockMinutes = v ?? 5),
                  ),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.exit_to_app),
                  title: const Text('切到后台立即锁定'),
                  value: st.lockOnBackground,
                  onChanged: (v) => st.update((x) => x.lockOnBackground = v),
                ),
                ListTile(
                  leading: const Icon(Icons.content_paste_off),
                  title: const Text('自动清除剪贴板'),
                  trailing: DropdownButton<int>(
                    value: st.clipboardClearSeconds,
                    underline: const SizedBox.shrink(),
                    items: const [
                      DropdownMenuItem(value: 15, child: Text('15 秒')),
                      DropdownMenuItem(value: 30, child: Text('30 秒')),
                      DropdownMenuItem(value: 60, child: Text('1 分钟')),
                      DropdownMenuItem(value: 120, child: Text('2 分钟')),
                      DropdownMenuItem(value: 0, child: Text('不清除')),
                    ],
                    onChanged: (v) => st.update((x) => x.clipboardClearSeconds = v ?? 30),
                  ),
                ),
                if (Platform.isAndroid)
                  SwitchListTile(
                    secondary: const Icon(Icons.screenshot_monitor),
                    title: const Text('禁止截屏'),
                    subtitle: const Text('同时在最近任务中隐藏内容'),
                    value: st.secureScreen,
                    onChanged: (v) {
                      st.update((x) => x.secureScreen = v);
                      SystemBridge.setSecureScreen(v);
                    },
                  ),
                if (s != null && !s.offline)
                  ListTile(
                    leading: const Icon(Icons.key_rounded),
                    title: const Text('修改主密码'),
                    onTap: _changeMasterPassword,
                  ),
              ]),
              if (Platform.isAndroid) ...[
                const SizedBox(height: 16),
                SectionCard(title: '自动填充', children: [
                  ListTile(
                    leading: Icon(
                      _autofillEnabled ? Icons.check_circle : Icons.error_outline,
                      color: _autofillEnabled
                          ? Colors.green
                          : Theme.of(context).colorScheme.tertiary,
                    ),
                    title: Text(_autofillEnabled ? '已启用 PassVault 自动填充' : '未启用自动填充'),
                    subtitle: Text(_autofillSupported
                        ? '在其他 App 或浏览器的登录框中，点击输入框即可选择账号填入'
                        : '当前系统不支持自动填充（需要 Android 8.0 以上）'),
                    trailing: _autofillSupported && !_autofillEnabled
                        ? FilledButton.tonal(
                            style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                            onPressed: SystemBridge.requestAutofill,
                            child: const Text('去开启'),
                          )
                        : null,
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.bolt),
                    title: const Text('只匹配到一个账号时直接填入'),
                    value: st.autofillAutoPickSingle,
                    onChanged: (v) => st.update((x) => x.autofillAutoPickSingle = v),
                  ),
                ]),
              ],
              if (s != null && s.isDirty) ...[
                const SizedBox(height: 16),
                FilledButton.tonalIcon(
                  onPressed: () => saveSession(context, s),
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: const Text('立即保存'),
                ),
              ],
              const SizedBox(height: 16),
              SectionCard(title: '关于', children: [
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('PassVault'),
                  subtitle: Text('版本 $_version · KeePass KDBX 3/4 兼容'),
                ),
                ListTile(
                  leading: const Icon(Icons.memory),
                  title: const Text('Argon2 加速'),
                  subtitle: Text(Vault.usingNativeArgon2 ? '原生加速已启用' : '使用兼容模式（解锁会稍慢）'),
                ),
              ]),
              const SizedBox(height: 8),
              Text(
                '所有数据只保存在你的密码库文件中，PassVault 不连接任何服务器。',
                textAlign: TextAlign.center,
                style: text.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
