import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:kdbx/kdbx.dart';

import '../core/matcher.dart';
import '../core/session.dart';
import '../core/settings.dart';
import '../core/totp.dart';
import '../core/vault.dart';
import '../ui/theme.dart';
import '../ui/unlock_page.dart';
import '../ui/widgets.dart';

/// 一次自动填充请求
class FillRequest {
  FillRequest({this.packageName, this.webDomain, this.appLabel});

  final String? packageName;
  final String? webDomain;
  final String? appLabel;

  String get targetLabel {
    if (webDomain != null && webDomain!.isNotEmpty) return webDomain!;
    if (appLabel != null && appLabel!.isNotEmpty) return appLabel!;
    return packageName ?? '当前应用';
  }

  static FillRequest? fromMap(Map? m) {
    if (m == null) return null;
    String? s(String k) {
      final v = m[k] as String?;
      return v == null || v.isEmpty ? null : v;
    }

    return FillRequest(
      packageName: s('package'),
      webDomain: s('domain'),
      appLabel: s('label'),
    );
  }
}

/// 自动填充引擎中的状态。引擎在填充结束后不会销毁，
/// 解锁状态会保留到超时，期间再次填充可以一键完成（无需再验证）。
class AutofillController extends ChangeNotifier {
  AutofillController(this.settings) {
    _ch.setMethodCallHandler(_onCall);
  }

  static const _ch = MethodChannel('passvault/autofill');

  Settings settings;
  VaultSession? session;
  FillRequest? request;
  Timer? _lockTimer;

  Future<dynamic> _onCall(MethodCall call) async {
    switch (call.method) {
      case 'newRequest':
        await settings.reload();
        request = FillRequest.fromMap(call.arguments as Map?);
        notifyListeners();
        return null;
      case 'query':
        // 原生服务询问：已解锁则直接返回匹配的账号，系统可在键盘/下拉中直接显示
        final s = session;
        if (s == null) return null;
        final r = FillRequest.fromMap(call.arguments as Map?);
        if (r == null) return null;
        final matches = EntryMatcher.match(
          s.vault.entries,
          packageName: r.packageName,
          webDomain: r.webDomain,
        );
        return [
          for (final e in matches.take(5))
            {
              'title': e.title,
              'username': e.userName,
              'password': e.password,
            },
        ];
      case 'lock':
        lock();
        return null;
    }
    return null;
  }

  void setSession(VaultSession s) {
    session?.close();
    session = s;
    _restartLockTimer();
    notifyListeners();
  }

  void _restartLockTimer() {
    _lockTimer?.cancel();
    final m = settings.autoLockMinutes;
    if (m > 0) _lockTimer = Timer(Duration(minutes: m), lock);
  }

  void lock() {
    _lockTimer?.cancel();
    final s = session;
    if (s == null) return;
    if (s.isDirty) {
      s.save().whenComplete(() {
        if (session == s) {
          s.close();
          session = null;
          notifyListeners();
        }
      });
      return;
    }
    s.close();
    session = null;
    notifyListeners();
  }

  /// 填入账号。[link] 为 true 时把当前 App/网站关联到该条目并保存，下次自动匹配。
  Future<void> fill(KdbxEntry e, {bool link = false}) async {
    final r = request;
    final totp = TotpConfig.fromFields(e.allFields);
    await _ch.invokeMethod('fill', {
      'username': e.userName,
      'password': e.password,
      'title': e.title,
      'otp': totp?.codeAt(DateTime.now()),
    });
    request = null;
    notifyListeners();
    _restartLockTimer();
    final s = session;
    if (link && r != null && s != null && !s.offline) {
      if (r.packageName != null && !_isBrowser(r.packageName!)) {
        EntryMatcher.linkApp(e, r.packageName!);
      }
      if (r.webDomain != null) EntryMatcher.linkDomain(e, r.webDomain!);
      if (s.isDirty) {
        try {
          await s.save();
        } catch (_) {
          // 静默失败：下次打开主程序时会提示未保存
        }
      }
    }
  }

  Future<void> cancel() async {
    request = null;
    notifyListeners();
    await _ch.invokeMethod('cancel');
  }

  static bool _isBrowser(String pkg) => const {
        'com.android.chrome',
        'com.chrome.beta',
        'com.chrome.dev',
        'org.mozilla.firefox',
        'org.mozilla.firefox_beta',
        'com.microsoft.emmx',
        'com.brave.browser',
        'com.opera.browser',
        'com.vivaldi.browser',
        'com.sec.android.app.sbrowser',
        'com.UCMobile',
        'com.tencent.mtt',
        'com.huawei.browser',
        'com.heytap.browser',
        'com.android.browser',
        'com.mi.globalbrowser',
        'com.duckduckgo.mobile.android',
        'com.kiwibrowser.browser',
      }.contains(pkg);

  Future<void> init() async {
    final m = await _ch.invokeMethod<Map>('getRequest');
    request = FillRequest.fromMap(m);
    notifyListeners();
  }
}

Future<void> runAutofillApp() async {
  final settings = await Settings.load();
  final c = AutofillController(settings);
  runApp(AutofillApp(controller: c));
  await c.init();
}

class AutofillApp extends StatelessWidget {
  const AutofillApp({super.key, required this.controller});

  final AutofillController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final seed = Color(controller.settings.seedColor);
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          themeMode: controller.settings.themeMode,
          theme: buildTheme(seed, Brightness.light),
          darkTheme: buildTheme(seed, Brightness.dark),
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: _AutofillHome(controller: controller),
        );
      },
    );
  }
}

class _AutofillHome extends StatelessWidget {
  const _AutofillHome({required this.controller});

  final AutofillController controller;

  @override
  Widget build(BuildContext context) {
    final r = controller.request;
    if (r == null) return const Scaffold(body: SizedBox.shrink());
    final source = controller.settings.lastSource;
    final scheme = Theme.of(context).colorScheme;
    Widget body;
    if (source == null) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.folder_off_outlined, size: 56, color: scheme.outline),
              const SizedBox(height: 16),
              const Text('请先打开 PassVault 并打开你的密码库，之后即可在这里自动填充。',
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    } else if (controller.session == null) {
      body = UnlockView(
        key: ValueKey('unlock-${source.id}-${r.hashCode}'),
        source: source,
        settings: controller.settings,
        subtitle: '为「${r.targetLabel}」填充账号',
        onUnlocked: (s) {
          controller.setSession(s);
          _maybeAutoPick(controller);
        },
      );
    } else {
      body = _Picker(key: ValueKey(r), controller: controller);
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) controller.cancel();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(icon: const Icon(Icons.close), onPressed: controller.cancel),
          title: const Text('PassVault 自动填充'),
        ),
        body: SafeArea(child: body),
      ),
    );
  }

  static void _maybeAutoPick(AutofillController c) {
    final s = c.session;
    final r = c.request;
    if (s == null || r == null || !c.settings.autofillAutoPickSingle) return;
    final m = EntryMatcher.match(s.vault.entries, packageName: r.packageName, webDomain: r.webDomain);
    if (m.length == 1) c.fill(m.first);
  }
}

class _Picker extends StatefulWidget {
  const _Picker({super.key, required this.controller});

  final AutofillController controller;

  @override
  State<_Picker> createState() => _PickerState();
}

class _PickerState extends State<_Picker> {
  final _q = TextEditingController();
  bool _remember = true;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final s = c.session!;
    final r = c.request!;
    final matches = EntryMatcher.match(s.vault.entries, packageName: r.packageName, webDomain: r.webDomain);
    final searching = _q.text.trim().isNotEmpty;
    final others = searching ? s.vault.search(_q.text) : s.vault.search('');
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    Widget tile(KdbxEntry e, {required bool matched}) => ListTile(
          leading: EntryAvatar(title: e.title),
          title: Text(e.title.isEmpty ? '（无标题）' : e.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(e.userName.isEmpty ? '（无用户名）' : e.userName,
              maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: const Icon(Icons.input_rounded),
          onTap: () => c.fill(e, link: !matched && _remember),
        );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: [
              Icon(Icons.apps_rounded, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text('填充到：${r.targetLabel}',
                    style: text.titleSmall, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SearchBar(
            controller: _q,
            hintText: '搜索全部账号',
            leading: const Icon(Icons.search),
            elevation: const WidgetStatePropertyAll(0),
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: [
              if (!searching && matches.isNotEmpty) ...[
                _header(context, '匹配的账号'),
                for (final e in matches) tile(e, matched: true),
                const SizedBox(height: 8),
              ],
              if (!searching && matches.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('没有自动匹配到账号，可以从下面选择或搜索。选中后会记住，下次自动匹配。',
                      style: text.bodySmall),
                ),
              _header(context, searching ? '搜索结果' : '全部账号'),
              for (final e in others)
                if (searching || !matches.contains(e)) tile(e, matched: matches.contains(e)),
            ],
          ),
        ),
        if (!s.offline)
          CheckboxListTile(
            value: _remember,
            onChanged: (v) => setState(() => _remember = v ?? true),
            title: const Text('记住选择，下次自动匹配'),
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
          ),
      ],
    );
  }

  Widget _header(BuildContext context, String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Text(t,
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );
}
