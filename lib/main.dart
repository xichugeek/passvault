import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'app_state.dart';
import 'autofill/autofill_app.dart';
import 'core/settings.dart';
import 'core/vault_source.dart';
import 'platform/system_bridge.dart';
import 'ui/home_page.dart';
import 'ui/theme.dart';
import 'ui/unlock_page.dart';
import 'ui/vault_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await Settings.load();
  if (settings.secureScreen) SystemBridge.setSecureScreen(true);
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState(settings),
      child: const PassVaultApp(),
    ),
  );
}

/// 安卓自动填充使用的独立入口（由原生 AutofillActivity 启动）
@pragma('vm:entry-point')
Future<void> autofillMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  await runAutofillApp();
}

const supportedLocales = [Locale('zh', 'CN'), Locale('en')];
const localizationsDelegates = [
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

class PassVaultApp extends StatelessWidget {
  const PassVaultApp({super.key});

  @override
  Widget build(BuildContext context) {
    final st = context.select((AppState a) => (a.settings.themeMode, a.settings.seedColor));
    final seed = Color(st.$2);
    return MaterialApp(
      title: 'PassVault',
      debugShowCheckedModeBanner: false,
      themeMode: st.$1,
      theme: buildTheme(seed, Brightness.light),
      darkTheme: buildTheme(seed, Brightness.dark),
      locale: const Locale('zh', 'CN'),
      supportedLocales: supportedLocales,
      localizationsDelegates: localizationsDelegates,
      home: const AppRoot(),
    );
  }
}

/// 根据状态切换：首页 / 解锁 / 密码库
class AppRoot extends StatefulWidget {
  const AppRoot({super.key});

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  VaultSource? _target;
  bool _showHome = false;

  bool _onKey(KeyEvent e) {
    context.read<AppState>().userActivity();
    return false;
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    Widget page;
    if (app.isUnlocked) {
      page = VaultPage(
        key: ValueKey(app.session!.source.id),
        onSwitchVault: () => setState(() {
          _showHome = true;
          _target = null;
        }),
      );
    } else {
      final target = _target ?? app.settings.lastSource;
      if (_showHome || target == null) {
        page = HomePage(
          onPick: (s) => setState(() {
            _target = s;
            _showHome = false;
          }),
        );
      } else {
        page = UnlockPage(
          source: target,
          onSwitchVault: () => setState(() => _showHome = true),
        );
      }
    }
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => app.userActivity(),
      child: AnimatedSwitcher(
        duration: kIsWeb ? Duration.zero : const Duration(milliseconds: 250),
        child: page,
      ),
    );
  }
}
