// ignore_for_file: invalid_use_of_visible_for_testing_member
// 生成界面截图用于人工检查（不在 CI 中运行）：
//   flutter test tool/screens/screens_test.dart
// 需要本机有 Noto Sans CJK 字体。
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kdbx/kdbx.dart';
import 'package:passvault/app_state.dart';
import 'package:passvault/core/argon2_native.dart';
import 'package:passvault/core/session.dart';
import 'package:passvault/core/settings.dart';
import 'package:passvault/core/templates.dart';
import 'package:passvault/core/vault.dart';
import 'package:passvault/core/vault_source.dart';
import 'package:passvault/ui/theme.dart';
import 'package:passvault/ui/vault_page.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

final outDir = Directory(Platform.environment['SHOT_DIR'] ?? 'build/screens');
final _shotKey = GlobalKey();

Future<void> loadFonts() async {
  Future<void> load(String family, String path) async {
    final f = File(path);
    if (!f.existsSync()) return;
    final loader = FontLoader(family)..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
    await loader.load();
  }

  const cjk = '/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc';
  final cjkFont = File(cjk).existsSync() ? cjk : '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc';
  await load('Roboto', cjkFont);
  await load('MaterialIcons', '/opt/sdk/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
}

Future<VaultSession> buildDemo() async {
  final dir = Directory.systemTemp.createTempSync('pvshot');
  final session = await VaultSession.create(
    LocalFileSource('${dir.path}/James'),
    'James',
    Vault.credentials('pw-12345678', null),
  );
  final v = session.vault;
  for (final g in v.childGroups(v.root).toList()) {
    v.deleteGroup(g);
  }
  v.emptyRecycleBin();
  v.recycleBin!.name.set('回收站');

  KdbxEntry add(KdbxGroup g, String title, String user, {KdbxIcon icon = KdbxIcon.Key, String url = ''}) {
    final e = v.createEntry(g);
    e.setStr(Fields.title, title);
    e.setStr(Fields.userName, user);
    e.setStr(Fields.password, 'S3cure!pass-${title.length}', protect: true);
    if (url.isNotEmpty) e.setStr(Fields.url, url);
    e.icon.set(icon);
    return e;
  }

  final fin = v.createGroup('1.金融账户', icon: KdbxIcon.Homebanking);
  final paypal = v.createGroup('PayPal', parent: fin, icon: KdbxIcon.Money);
  final bank = v.createGroup('银行', parent: fin, icon: KdbxIcon.Homebanking);
  final mail = v.createGroup('2.邮箱账户', icon: KdbxIcon.EMail);
  final social = v.createGroup('3.社交账户', icon: KdbxIcon.UserCommunication);
  final work = v.createGroup('4.工作', icon: KdbxIcon.Folder);
  v.createGroup('5.服务器', icon: KdbxIcon.NetworkServer);
  v.createGroup('6.其他', icon: KdbxIcon.Folder);

  add(paypal, 'PayPal 主账户', 'james@example.com', icon: KdbxIcon.Money, url: 'https://paypal.com');
  add(paypal, 'PayPal 商家', 'shop@example.com', icon: KdbxIcon.Money);
  add(bank, '招商银行', '6225****1234', icon: KdbxIcon.Homebanking);
  add(fin, '支付宝', '138****8888', icon: KdbxIcon.Money, url: 'https://alipay.com');
  add(fin, '10.Interactive Brokers', 'james_ib', icon: KdbxIcon.Homebanking);
  add(fin, '2.富途证券', 'james', icon: KdbxIcon.Homebanking);
  add(mail, 'Gmail', 'james@gmail.com', icon: KdbxIcon.EMail, url: 'https://mail.google.com');
  add(mail, 'QQ 邮箱', '12345678@qq.com', icon: KdbxIcon.EMailBox);
  add(social, '微信', 'james_wx', icon: KdbxIcon.UserCommunication);
  add(social, 'GitHub', 'xichugeek', icon: KdbxIcon.Console, url: 'https://github.com');
  add(work, '公司 VPN', 'james', icon: KdbxIcon.TerminalEncrypted);
  add(v.root, '家里 Wi-Fi', '', icon: KdbxIcon.IRCommunication);

  final t = Templates(v);
  final cc = t.createFrom(t.available.firstWhere((x) => x.builtinId == 'creditcard'), fin);
  cc.setStr(Fields.title, '招商银行信用卡');
  cc.setStr('卡号', '6225 8812 3456 7890');
  cc.setStr('CVV', '123', protect: true);
  cc.setStr('PIN', '888888', protect: true);
  cc.setStr('持卡人', 'JAMES');
  cc.expiry = DateTime(2029, 12, 31, 23, 59);
  final old = add(work, '旧系统账号', 'james_old', icon: KdbxIcon.Key);
  v.deleteEntry(old);
  await session.save();
  return session;
}

Future<void> shot(WidgetTester tester, String name) async {
  await tester.pump(const Duration(milliseconds: 400));
  final boundary = _shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final img = await boundary.toImage(pixelRatio: tester.view.devicePixelRatio);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    outDir.createSync(recursive: true);
    File('${outDir.path}/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
  });
}

Widget app(AppState state, {Brightness b = Brightness.light}) => ChangeNotifierProvider.value(
      value: state,
      child: RepaintBoundary(
        key: _shotKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme(const Color(0xFF3D5AFE), Brightness.light),
          darkTheme: buildTheme(const Color(0xFF3D5AFE), Brightness.dark),
          themeMode: b == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
          home: VaultPage(onSwitchVault: () {}),
        ),
      ),
    );

void main() {
  late AppState state;

  setUpAll(() async {
    NativeArgon2.libraryPathOverride = '${Directory.current.path}/build/native/libpv_argon2.so';
    Vault.format = KdbxFormat(NativeArgon2.tryLoad());
  });

  Future<void> setup(WidgetTester tester, Size size, double dpr) async {
    SharedPreferences.setMockInitialValues({});
    await tester.runAsync(loadFonts);
    final settings = await tester.runAsync(Settings.load);
    state = AppState(settings!);
    final s = await tester.runAsync(buildDemo);
    state.setSession(s!);
    debugDisableShadows = false;
    tester.view.physicalSize = size * dpr;
    tester.view.devicePixelRatio = dpr;
  }

  testWidgets('手机', (tester) async {
    await setup(tester, const Size(400, 860), 2);
    await tester.pumpWidget(app(state));
    await shot(tester, 'phone_1_root');

    await tester.tap(find.text('1.金融账户'));
    await tester.pump(const Duration(milliseconds: 500));
    await shot(tester, 'phone_2_group');

    await tester.tap(find.text('新建'));
    await tester.pump(const Duration(milliseconds: 600));
    await shot(tester, 'phone_3_new');
    await tester.tapAt(const Offset(200, 40));
    await tester.pump(const Duration(milliseconds: 600));

    await tester.tap(find.text('招商银行信用卡'));
    await tester.pump(const Duration(milliseconds: 600));
    await shot(tester, 'phone_4_card');

    await tester.tap(find.byTooltip('编辑'));
    await tester.pump(const Duration(milliseconds: 600));
    await shot(tester, 'phone_5_edit');
    state.lock();
    debugDisableShadows = true;
  });

  testWidgets('电脑', (tester) async {
    await setup(tester, const Size(1400, 860), 1);
    await tester.pumpWidget(app(state));
    await tester.tap(find.text('1.金融账户').first);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('招商银行信用卡'));
    await tester.pump(const Duration(milliseconds: 400));
    await shot(tester, 'desktop_1');

    await tester.pumpWidget(app(state, b: Brightness.dark));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('1.金融账户').first);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('PayPal').first);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('PayPal 主账户'));
    await tester.pump(const Duration(milliseconds: 400));
    await shot(tester, 'desktop_2_dark');

    await tester.tap(find.byIcon(Icons.edit_outlined).first);
    await tester.pump(const Duration(milliseconds: 600));
    await shot(tester, 'desktop_3_edit');
    await tester.tap(find.byTooltip('更换图标'));
    await tester.pump(const Duration(milliseconds: 600));
    await shot(tester, 'desktop_4_icons');
    state.lock();
    debugDisableShadows = true;
  });
}
