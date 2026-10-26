# PassVault

一款界面现代、自动填充顺手的 **KeePass 兼容**密码管理器，Windows 与 Android 共用同一个 `.kdbx` 密码库，通过 Google Drive 同步。

## 功能

- **完全兼容 KeePass**：读写 KDBX 3.1 / 4.x（AES-KDF、Argon2d、Argon2id，AES-256 / ChaCha20），支持密钥文件；与 KeePassXC、Keepass2Android、KeePassDX 互通
- **两端同步**：Windows 打开"Google Drive 电脑版"同步文件夹里的文件；安卓通过系统文件选择器直接读写 Google Drive 中的同一个文件
- **自动合并**：两台设备都改过时，保存前自动合并，不会互相覆盖
- **安卓自动填充**：按 App 包名 / 网页域名自动匹配；解锁后几分钟内可在输入框下拉或键盘上方一键填入；未匹配时选中账号可"记住选择"
- **快速解锁**：安卓指纹/面容（Android Keystore 硬件加密），Windows Hello
- **两步验证码（TOTP）**：兼容 KeePassXC / KeePass / Keepass2Android 的存储格式
- **其它**：密码生成器、强度提示、剪贴板自动清除、无操作自动锁定、防截屏、深色模式、宽屏双栏布局、快捷键（Ctrl+F / Ctrl+N / Ctrl+L）
- **原生加速**：Argon2 与 AES-KDF 使用 C 实现，AES 走 CPU 硬件指令（AES-NI / ARMv8），解锁通常在 1 秒内

## 下载安装

每次推送到 `main` 分支，GitHub Actions 会自动打包并发布到 [Releases](../../releases)：

| 平台 | 文件 |
| --- | --- |
| Android 8.0+ | `PassVault-android.apk` |
| Windows 10/11 x64 | `PassVault-setup.exe`（安装版）或 `PassVault-windows.zip`（免安装） |

## 首次使用

**Windows**
1. 安装 [Google Drive 电脑版](https://www.google.com/drive/download/) 并登录
2. 打开 PassVault →"打开密码库"→ 选择 Google Drive 文件夹（如 `G:\我的云端硬盘`）里的 `.kdbx`

**Android**
1. 打开 PassVault →"打开密码库"→ 左上角菜单选 Google Drive → 选择同一个 `.kdbx`
2. 解锁后按提示开启指纹解锁
3. 设置 → 自动填充 →"去开启"，在系统列表中选择 PassVault

## Android 签名（可选，建议配置）

为了让每次新版本 APK 都能直接覆盖安装（不丢失指纹解锁、最近文件等设置），在仓库 **Settings → Secrets and variables → Actions** 中添加：

- `ANDROID_KEYSTORE_BASE64`：签名文件（.jks）的 Base64
- `ANDROID_KEYSTORE_PASSWORD`：签名文件密码

未配置时使用临时签名，升级前需要先卸载旧版本（密码数据在 Google Drive，不受影响）。

## 本地开发

```bash
flutter pub get
# 编译测试用的原生库（Linux/macOS）
mkdir -p build/native && cd build/native && cmake ../../native && make && cd ../..
flutter test
flutter run -d windows   # 或连接安卓手机
```

## 目录结构

```
lib/
  core/        密码库读写、同步合并、匹配、TOTP、密码生成
  platform/    安卓文件访问、指纹解锁、系统功能
  ui/          界面
  autofill/    安卓自动填充界面（独立 Dart 入口）
android/       原生代码：自动填充服务、Keystore、SAF
native/        Argon2 / AES-KDF 的 C 实现
packages/kdbx  KDBX 格式库（基于 kdbx.dart，增加了 Argon2id 与原生 AES-KDF 支持）
```

## 许可

本项目使用的 KDBX 格式库 [kdbx.dart](https://github.com/authpass/kdbx.dart) 采用 GPL-3.0 许可，因此本项目整体同样遵循 **GPL-3.0**。Argon2 参考实现采用 CC0 / Apache-2.0。
