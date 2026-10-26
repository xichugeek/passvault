import 'package:kdbx/kdbx.dart';

import 'vault.dart';

/// 自动填充匹配：根据 App 包名或网页域名找出相关条目。
///
/// 兼容各家 KeePass 客户端的关联方式：
/// - Keepass2Android：URL 字段写成 `androidapp://包名`，额外网址放在 `KP2A_URL_*`
/// - KeePassDX：自定义字段 `AndroidApp`、`AndroidApp_1`…
/// - KeePassXC：`KP2A_URL*`、`URL_*` 额外网址
class EntryMatcher {
  /// 一些 App 包名与网站的已知对应，提升首次匹配命中率
  static const _knownApps = <String, List<String>>{
    'com.tencent.mm': ['weixin.qq.com', 'wx.qq.com'],
    'com.tencent.mobileqq': ['qq.com'],
    'com.taobao.taobao': ['taobao.com'],
    'com.tmall.wireless': ['tmall.com'],
    'com.jingdong.app.mall': ['jd.com'],
    'com.eg.android.AlipayGphone': ['alipay.com'],
    'com.sina.weibo': ['weibo.com'],
    'com.ss.android.ugc.aweme': ['douyin.com'],
    'tv.danmaku.bili': ['bilibili.com'],
    'com.xingin.xhs': ['xiaohongshu.com'],
    'com.netease.cloudmusic': ['music.163.com'],
    'com.zhihu.android': ['zhihu.com'],
    'com.github.android': ['github.com'],
    'com.google.android.gm': ['google.com', 'gmail.com'],
    'com.twitter.android': ['twitter.com', 'x.com'],
    'com.facebook.katana': ['facebook.com'],
    'com.instagram.android': ['instagram.com'],
    'com.microsoft.office.outlook': ['outlook.com', 'live.com', 'microsoft.com'],
    'com.discord': ['discord.com'],
    'org.telegram.messenger': ['telegram.org'],
    'com.spotify.music': ['spotify.com'],
    'com.netflix.mediaclient': ['netflix.com'],
    'com.amazon.mShop.android.shopping': ['amazon.com'],
    'com.linkedin.android': ['linkedin.com'],
    'com.reddit.frontpage': ['reddit.com'],
    'com.paypal.android.p2pmobile': ['paypal.com'],
    'com.steam.community': ['steampowered.com', 'steamcommunity.com'],
    'com.valvesoftware.android.steam.community': ['steampowered.com', 'steamcommunity.com'],
  };

  /// 返回按相关度排序的匹配条目
  static List<KdbxEntry> match(
    List<KdbxEntry> entries, {
    String? packageName,
    String? webDomain,
  }) {
    final scored = <KdbxEntry, int>{};
    final domain = webDomain == null || webDomain.isEmpty
        ? null
        : _normalizeHost(webDomain);
    final pkg = packageName == null || packageName.isEmpty ? null : packageName;
    final pkgDomains = pkg == null ? const <String>[] : (_knownApps[pkg] ?? const []);
    final pkgTokens = pkg == null ? const <String>[] : _packageTokens(pkg);

    for (final e in entries) {
      var best = 0;
      final apps = appsOf(e);
      final urls = urlsOf(e);

      if (pkg != null && apps.contains(pkg)) best = 100;

      for (final u in urls) {
        final host = _hostOf(u);
        if (host == null) continue;
        if (domain != null) {
          if (host == domain) {
            best = best < 95 ? 95 : best;
          } else if (_sameSite(host, domain)) {
            best = best < 85 ? 85 : best;
          }
        }
        if (pkg != null) {
          for (final d in pkgDomains) {
            if (_sameSite(host, d)) best = best < 80 ? 80 : best;
          }
          // 例如 com.example.app ↔ example.com
          final site = _registrable(host);
          final siteName = site.split('.').first;
          if (siteName.length >= 3 && pkgTokens.contains(siteName)) {
            best = best < 60 ? 60 : best;
          }
        }
      }

      if (best == 0 && pkg != null) {
        // 标题包含包名中的关键词（较弱匹配）
        final t = e.title.toLowerCase();
        for (final tok in pkgTokens) {
          if (tok.length >= 4 && t.contains(tok)) {
            best = 30;
            break;
          }
        }
      }
      if (best == 0 && domain != null) {
        final siteName = _registrable(domain).split('.').first;
        if (siteName.length >= 3 && e.title.toLowerCase().contains(siteName)) {
          best = 30;
        }
      }
      if (best > 0) scored[e] = best;
    }
    final list = scored.keys.toList()
      ..sort((a, b) {
        final c = scored[b]!.compareTo(scored[a]!);
        if (c != 0) return c;
        return a.title.compareTo(b.title);
      });
    // 有强匹配时丢弃弱匹配，避免误填
    if (list.isNotEmpty && scored[list.first]! >= 60) {
      return list.where((e) => scored[e]! >= 60).toList();
    }
    return list;
  }

  static Set<String> appsOf(KdbxEntry e) {
    final out = <String>{};
    for (final kv in e.allFields.entries) {
      final k = kv.key;
      final v = kv.value.trim();
      if (v.isEmpty) continue;
      if (k == Fields.androidApp || k.startsWith('${Fields.androidApp}_')) {
        out.add(v);
      }
      if (k == Fields.url || k.startsWith('KP2A_URL') || k.startsWith('URL_')) {
        if (v.toLowerCase().startsWith('androidapp://')) {
          out.add(v.substring('androidapp://'.length).split('/').first);
        }
      }
    }
    return out;
  }

  static List<String> urlsOf(KdbxEntry e) {
    final out = <String>[];
    for (final kv in e.allFields.entries) {
      final k = kv.key;
      final v = kv.value.trim();
      if (v.isEmpty || v.toLowerCase().startsWith('androidapp://')) continue;
      if (k == Fields.url || k.startsWith('KP2A_URL') || k.startsWith('URL_') ||
          k == 'KPH: URL') {
        out.add(v);
      }
    }
    return out;
  }

  /// 把 App 包名关联到条目，下次自动匹配
  static void linkApp(KdbxEntry e, String packageName) {
    if (appsOf(e).contains(packageName)) return;
    final fields = e.allFields;
    var key = Fields.androidApp;
    var i = 1;
    while (fields.containsKey(key)) {
      key = '${Fields.androidApp}_$i';
      i++;
    }
    e.setStr(key, packageName);
  }

  /// 把网页域名关联到条目
  static void linkDomain(KdbxEntry e, String domain) {
    final d = _normalizeHost(domain);
    for (final u in urlsOf(e)) {
      final h = _hostOf(u);
      if (h != null && _sameSite(h, d)) return;
    }
    if (e.url.trim().isEmpty) {
      e.setStr(Fields.url, 'https://$d');
      return;
    }
    final fields = e.allFields;
    var i = 1;
    while (fields.containsKey('KP2A_URL_$i')) {
      i++;
    }
    e.setStr('KP2A_URL_$i', 'https://$d');
  }

  static String _normalizeHost(String h) {
    var s = h.trim().toLowerCase();
    if (s.startsWith('www.')) s = s.substring(4);
    return s;
  }

  static String? _hostOf(String url) {
    var u = url.trim();
    if (u.isEmpty) return null;
    if (!u.contains('://')) u = 'https://$u';
    final uri = Uri.tryParse(u);
    if (uri == null || uri.host.isEmpty) return null;
    return _normalizeHost(uri.host);
  }

  static const _twoLevelTlds = {
    'com.cn', 'net.cn', 'org.cn', 'gov.cn', 'edu.cn', 'co.uk', 'org.uk',
    'ac.uk', 'co.jp', 'ne.jp', 'or.jp', 'com.hk', 'com.tw', 'com.au',
    'net.au', 'co.kr', 'com.sg', 'com.br', 'co.in', 'co.nz',
  };

  /// 可注册域名，如 login.account.example.com.cn → example.com.cn
  static String _registrable(String host) {
    final parts = host.split('.');
    if (parts.length <= 2) return host;
    final last2 = parts.sublist(parts.length - 2).join('.');
    if (_twoLevelTlds.contains(last2) && parts.length >= 3) {
      return parts.sublist(parts.length - 3).join('.');
    }
    return last2;
  }

  static bool _sameSite(String a, String b) =>
      _registrable(_normalizeHost(a)) == _registrable(_normalizeHost(b));

  static const _ignoredTokens = {
    'com', 'org', 'net', 'android', 'app', 'apps', 'mobile', 'client', 'www',
    'cn', 'io', 'co', 'main', 'lite', 'global', 'intl', 'release',
  };

  static List<String> _packageTokens(String pkg) => pkg
      .toLowerCase()
      .split(RegExp(r'[._]'))
      .where((t) => t.length >= 3 && !_ignoredTokens.contains(t))
      .toList();
}
