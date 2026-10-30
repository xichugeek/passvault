import 'package:flutter/material.dart';
import 'package:kdbx/kdbx.dart';

/// KeePass 的 69 个标准图标（按编号顺序）对应的现代图标与配色色相。
/// sat 为饱和度，0 表示灰色系。
class _K {
  const _K(this.icon, this.hue, [this.sat = 0.62]);
  final IconData icon;
  final double hue;
  final double sat;
}

const _icons = <_K>[
  _K(Icons.key_rounded, 38), // 0 Key
  _K(Icons.public_rounded, 212), // 1 World
  _K(Icons.warning_amber_rounded, 28), // 2 Warning
  _K(Icons.dns_rounded, 222, 0.35), // 3 NetworkServer
  _K(Icons.folder_special_rounded, 40), // 4 MarkedDirectory
  _K(Icons.forum_rounded, 168), // 5 UserCommunication
  _K(Icons.extension_rounded, 270), // 6 Parts
  _K(Icons.edit_note_rounded, 46), // 7 Notepad
  _K(Icons.lan_rounded, 200), // 8 WorldSocket
  _K(Icons.badge_rounded, 232), // 9 Identity
  _K(Icons.task_rounded, 140), // 10 PaperReady
  _K(Icons.photo_camera_rounded, 330), // 11 Digicam
  _K(Icons.wifi_rounded, 188), // 12 IRCommunication
  _K(Icons.vpn_key_rounded, 34), // 13 MultiKeys
  _K(Icons.power_settings_new_rounded, 2), // 14 Energy
  _K(Icons.document_scanner_rounded, 210, 0.35), // 15 Scanner
  _K(Icons.travel_explore_rounded, 216), // 16 WorldStar
  _K(Icons.album_rounded, 282), // 17 CDRom
  _K(Icons.monitor_rounded, 220, 0.35), // 18 Monitor
  _K(Icons.mail_rounded, 206), // 19 EMail
  _K(Icons.tune_rounded, 210, 0.2), // 20 Configuration
  _K(Icons.assignment_turned_in_rounded, 132), // 21 ClipboardReady
  _K(Icons.note_add_rounded, 160), // 22 PaperNew
  _K(Icons.desktop_windows_rounded, 226), // 23 Screen
  _K(Icons.electric_bolt_rounded, 42), // 24 EnergyCareful
  _K(Icons.inbox_rounded, 210), // 25 EMailBox
  _K(Icons.save_rounded, 232), // 26 Disk
  _K(Icons.storage_rounded, 215, 0.35), // 27 Drive
  _K(Icons.help_center_rounded, 262), // 28 PaperQ
  _K(Icons.terminal_rounded, 150), // 29 TerminalEncrypted
  _K(Icons.code_rounded, 215, 0.3), // 30 Console
  _K(Icons.print_rounded, 210, 0.2), // 31 Printer
  _K(Icons.apps_rounded, 265), // 32 ProgramIcons
  _K(Icons.rocket_launch_rounded, 18), // 33 Run
  _K(Icons.settings_rounded, 210, 0.2), // 34 Settings
  _K(Icons.computer_rounded, 208), // 35 WorldComputer
  _K(Icons.archive_rounded, 28, 0.45), // 36 Archive
  _K(Icons.account_balance_rounded, 150), // 37 Homebanking
  _K(Icons.window_rounded, 204), // 38 DriveWindows
  _K(Icons.schedule_rounded, 178), // 39 Clock
  _K(Icons.manage_search_rounded, 210), // 40 EMailSearch
  _K(Icons.flag_rounded, 354), // 41 PaperFlag
  _K(Icons.memory_rounded, 122), // 42 Memory
  _K(Icons.delete_rounded, 0, 0.15), // 43 TrashBin
  _K(Icons.sticky_note_2_rounded, 50), // 44 Note
  _K(Icons.cancel_rounded, 0), // 45 Expired
  _K(Icons.info_rounded, 206), // 46 Info
  _K(Icons.inventory_2_rounded, 28, 0.45), // 47 Package
  _K(Icons.folder_rounded, 40), // 48 Folder
  _K(Icons.folder_open_rounded, 40), // 49 FolderOpen
  _K(Icons.folder_zip_rounded, 34), // 50 FolderPackage
  _K(Icons.lock_open_rounded, 24), // 51 LockOpen
  _K(Icons.enhanced_encryption_rounded, 236), // 52 PaperLocked
  _K(Icons.check_circle_rounded, 134), // 53 Checked
  _K(Icons.draw_rounded, 282), // 54 Pen
  _K(Icons.image_rounded, 322), // 55 Thumbnail
  _K(Icons.menu_book_rounded, 24, 0.5), // 56 Book
  _K(Icons.list_alt_rounded, 215, 0.3), // 57 List
  _K(Icons.manage_accounts_rounded, 246), // 58 UserKey
  _K(Icons.build_rounded, 24, 0.3), // 59 Tool
  _K(Icons.home_rounded, 18), // 60 Home
  _K(Icons.star_rounded, 44), // 61 Star
  _K(Icons.pets_rounded, 30, 0.25), // 62 Tux
  _K(Icons.history_edu_rounded, 172), // 63 Feather
  _K(Icons.apple, 0, 0.0), // 64 Apple
  _K(Icons.auto_stories_rounded, 0, 0.0), // 65 Wiki
  _K(Icons.payments_rounded, 142), // 66 Money
  _K(Icons.workspace_premium_rounded, 40), // 67 Certificate
  _K(Icons.smartphone_rounded, 215, 0.3), // 68 BlackBerry
];

/// 每个标准图标的中文名（用于选择器提示）
const kpIconNames = <String>[
  '钥匙', '网站', '警告', '服务器', '标记文件夹', '聊天', '组件', '记事本', '网络', '身份证',
  '已完成', '相机', '无线', '多把钥匙', '电源', '扫描', '收藏网站', '光盘', '显示器', '邮件',
  '配置', '剪贴板', '新文档', '屏幕', '电力', '收件箱', '磁盘', '硬盘', '问题', '加密终端',
  '代码', '打印机', '应用', '启动', '设置', '电脑', '归档', '网上银行', 'Windows', '时钟',
  '邮件搜索', '旗帜', '内存', '回收站', '便签', '已过期', '信息', '包裹', '文件夹', '打开的文件夹',
  '压缩包', '解锁', '加密文档', '已确认', '笔', '图片', '书', '列表', '会员', '工具',
  '家', '星标', 'Linux', '羽毛笔', 'Apple', '百科', '钱', '证书', '手机',
];

int get kpIconCount => _icons.length;

IconData kpIconData(KdbxIcon? icon) => _icons[(icon ?? KdbxIcon.Key).index.clamp(0, _icons.length - 1)].icon;

({Color bg, Color fg}) kpIconColors(KdbxIcon? icon, Brightness b) {
  final k = _icons[(icon ?? KdbxIcon.Key).index.clamp(0, _icons.length - 1)];
  final dark = b == Brightness.dark;
  final bg = HSLColor.fromAHSL(1, k.hue, k.sat * 0.75, dark ? 0.24 : 0.92).toColor();
  final fg = HSLColor.fromAHSL(1, k.hue, k.sat, dark ? 0.78 : 0.40).toColor();
  return (bg: bg, fg: fg);
}

final _imageCache = <String, MemoryImage>{};

/// 显示条目或分组的图标：优先使用库里的自定义图标，否则用标准图标
class KpIcon extends StatelessWidget {
  const KpIcon({
    super.key,
    required this.icon,
    this.custom,
    this.size = 40,
    this.dimmed = false,
  });

  /// 便捷构造：根据条目/分组对象取图标
  factory KpIcon.of(KdbxObject o, {double size = 40, bool dimmed = false, Key? key}) {
    KdbxCustomIcon? custom;
    try {
      custom = o.customIcon;
    } catch (_) {}
    return KpIcon(key: key, icon: o.icon.get(), custom: custom, size: size, dimmed: dimmed);
  }

  final KdbxIcon? icon;
  final KdbxCustomIcon? custom;
  final double size;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    final radius = BorderRadius.circular(size * 0.3);
    Widget child;
    Color bg;
    if (custom != null && custom!.data.isNotEmpty) {
      final img = _imageCache.putIfAbsent(custom!.uuid.uuid, () => MemoryImage(custom!.data));
      bg = Theme.of(context).colorScheme.surfaceContainerHigh;
      child = Padding(
        padding: EdgeInsets.all(size * 0.16),
        child: Image(
          image: img,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, _, _) => Icon(kpIconData(icon), size: size * 0.55),
        ),
      );
    } else {
      final c = kpIconColors(icon, b);
      bg = c.bg;
      child = Icon(kpIconData(icon), size: size * 0.56, color: c.fg);
    }
    return Opacity(
      opacity: dimmed ? 0.55 : 1,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: bg, borderRadius: radius),
        child: child,
      ),
    );
  }
}

/// 图标选择结果
class IconChoice {
  const IconChoice.standard(KdbxIcon this.icon) : custom = null;
  const IconChoice.custom(KdbxCustomIcon this.custom) : icon = null;

  final KdbxIcon? icon;
  final KdbxCustomIcon? custom;

  void applyTo(KdbxObject o) {
    if (custom != null) {
      o.customIcon = custom;
    } else {
      if (o.customIconUuid.get() != null) o.customIcon = null;
      o.icon.set(icon!);
    }
  }
}

/// 弹出图标选择器
Future<IconChoice?> pickIcon(BuildContext context, KdbxFile file, {KdbxObject? current}) {
  final customs = file.body.meta.customIcons.values.toList();
  final currentIcon = current?.icon.get();
  final currentCustom = current?.customIconUuid.get();
  return showModalBottomSheet<IconChoice>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (c) {
      final text = Theme.of(c).textTheme;
      final scheme = Theme.of(c).colorScheme;
      Widget cell(Widget child, bool selected, VoidCallback onTap, String tip) => Tooltip(
            message: tip,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: onTap,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: selected ? scheme.primary : Colors.transparent,
                    width: 2,
                  ),
                ),
                alignment: Alignment.center,
                child: child,
              ),
            ),
          );
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (c, scroll) => CustomScrollView(
          controller: scroll,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              sliver: SliverToBoxAdapter(child: Text('选择图标', style: text.titleLarge)),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 64,
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 6,
                ),
                delegate: SliverChildBuilderDelegate(
                  (c, i) {
                    final ic = KdbxIcon.values[i];
                    return cell(
                      KpIcon(icon: ic, size: 44),
                      currentCustom == null && currentIcon == ic,
                      () => Navigator.pop(c, IconChoice.standard(ic)),
                      kpIconNames[i],
                    );
                  },
                  childCount: KdbxIcon.values.length,
                ),
              ),
            ),
            if (customs.isNotEmpty) ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                sliver: SliverToBoxAdapter(
                  child: Text('密码库中的自定义图标', style: text.titleSmall?.copyWith(color: scheme.primary)),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 64,
                    mainAxisSpacing: 6,
                    crossAxisSpacing: 6,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (c, i) => cell(
                      KpIcon(icon: null, custom: customs[i], size: 44),
                      currentCustom == customs[i].uuid,
                      () => Navigator.pop(c, IconChoice.custom(customs[i])),
                      '自定义图标',
                    ),
                    childCount: customs.length,
                  ),
                ),
              ),
            ] else
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      );
    },
  );
}
