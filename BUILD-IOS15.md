# OpenMinis iOS 15 版构建与安装指南

本源码树在官方 OpenMinis（GPLv3）基础上做了 **iOS 15.0 兼容改造**：官方 App Store 版本最低要求 iOS 16.0，这里把主 App 的部署目标降到 15.0，并用一套"影子 API 兼容层"补齐了 iOS 15 上缺失的 SwiftUI API。

---

## 一、本源码树改了什么

| 类别 | 内容 |
|---|---|
| 部署目标 | 主 App / Share 扩展 / FileProvider 扩展：16.0 → **15.0**；小组件保持 16.2（iOS 15 无锁屏小组件机制）；rclone 原生库构建下限 16.0 → 15.0 |
| 新增 `src/ios/Backports/` | 兼容层（5 个文件）：`NavigationStack`/`NavigationPath`/`navigationDestination`/`NavigationLink(value:)` 的 iOS 15 实现（基于 NavigationView + 隐藏 isActive 链 + UINavigationController 代理同步）；`presentationDetents`/`presentationDragIndicator`（走 UISheetPresentationController，iOS 15/16+ 行为一致）；`LabeledContent`、`AnyShape`、`UnevenRoundedRectangle`、`ShareLink`、`NavigationSplitView`、`toolbar(_:for:)`、`scrollDismissesKeyboard` 等影子实现；`UIHostingConfiguration`（基于 iOS 14 的 UIContentConfiguration/UIContentView，消息列表可用）；`PhotosPicker` 全套（PHPicker 方案，iOS 15/16+ 行为一致） |
| AppIntents（Siri 快捷指令） | 13 个意图文件整体加 `@available(iOS 16.0, *)`；响应文本解析逻辑抽到不受限制的 `SendPromptResponseParsing` 供 iOS 15 复用 |
| 调用点修补 | `TextField(axis:)` → `GrowingTextField`；`Font.monospaced()` → `Font.system(_:design:)`；View 级 `fontWeight` 移回 Text 链；`Color.gradient` → LinearGradient；范围 `lineLimit` 回移 |
| 原生依赖 | iSH / FFmpeg / LAME 官方本就按 iOS 14.0 下限编译，未改动 |

### iOS 15 上的功能差异（系统限制，无法回移）
- Siri 快捷指令 / App Intents（iOS 16 起才有该框架）
- 锁屏小组件与小组件交互（小组件 target 保持 16.2）
- 拖拽重排会话等个别 16+ 手势若被系统限制则降级
- 部分 iOS 16+ 的视觉细节（如工具栏背景材质覆盖）在 15 上使用系统默认样式

---

## 二、云端构建出 IPA（需要 GitHub 账号，免费）

1. 把本源码树（含 `.github/workflows/build-ios15-ipa.yml`）上传到你自己的 **公开 GitHub 仓库**
   - 方式 A：`git init` + push（推荐）
   - 方式 B：网页端 Upload files 直接拖入（注意保留目录结构，`.github` 开头目录也能传）
2. 仓库页 → **Actions** 标签 → 左侧 **Build iOS 15 IPA** → **Run workflow** → 确认
3. 首次构建约 40–70 分钟（要编译 iSH / FFmpeg / LAME / rclone；之后命中缓存约 15–25 分钟）
4. 构建成功后在该次运行页底部 **Artifacts** 下载 `OpenMinis-iOS15-unsigned-ipa`，解压得到 `OpenMinis-iOS15-unsigned.ipa`（**未签名**）

> 若构建失败：打开失败 step 的日志，把报错贴给助手迭代修复即可。

---

## 三、签名安装三选一

| 方式 | 适用 | 说明 |
|---|---|---|
| **TrollStore**（推荐，免签永久） | iOS 15.0–16.6.1（含 15.x 大部分版本，需先安装 TrollStore） | 直接用 TrollStore 打开 IPA 安装，无需 Apple ID，签名永久有效 |
| **Sideloadly / AltStore**（免费 Apple ID） | 任意 iOS 15 设备 | 电脑装 Sideloadly，接入 iPhone，拖入 IPA，用你的 Apple ID 签名（**7 天有效期**，到期重签）；HealthKit/iCloud 等需开发者账号的能力可能不可用 |
| **开发者证书**（$99/年账号） | 任意 iOS 15 设备 | 用 Xcode/爱思助手/FastSign 等以开发者证书签名，1 年有效；healthkit/homekit/icloud 等受限授权需在开发者后台匹配 |

> 提示：本 App 自带 Alpine Linux 沙盒（iSH 内核），安装包较大（数百 MB）属正常现象。

---

## 四、本地构建（可选，需 Mac）

```sh
git clone --recurse-submodules <你的仓库>
cd OpenMinis
./deps/build_lame.sh && ./deps/build_ffmpeg.sh && ./deps/build_ish.sh && ./deps/prepare_alpine_rootfs.sh && ./deps/build_rclone_ios.sh
open src/ios/Minis.xcodeproj   # Xcode 26+，scheme=Minis，目标 iOS 15.0
```

无签名命令行打包：
```sh
xcodebuild -project src/ios/Minis.xcodeproj -scheme Minis -configuration Release \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" build
# 产物在 build/Build/Products/Release-iphoneos/Minis.app，压成 Payload zip 即为 IPA
```

---

## 五、许可

OpenMinis 采用 **GPL v3**（因链接 iSH GPLv3 / PRoot GPLv2）。本改造版同样遵循 GPLv3 开源。
