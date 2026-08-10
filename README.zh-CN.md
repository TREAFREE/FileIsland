# File Island

[English](README.md) | [简体中文](README.zh-CN.md)

[![CI](https://github.com/TREAFREE/FileIsland/actions/workflows/ci.yml/badge.svg)](https://github.com/TREAFREE/FileIsland/actions/workflows/ci.yml)
[![最新版本](https://img.shields.io/github/v/release/TREAFREE/FileIsland)](https://github.com/TREAFREE/FileIsland/releases/latest)
[![下载量](https://img.shields.io/github/downloads/TREAFREE/FileIsland/total)](https://github.com/TREAFREE/FileIsland/releases)
[![macOS 15+](https://img.shields.io/badge/macOS-15%2B-111111?logo=apple)](https://github.com/TREAFREE/FileIsland/releases)
[![Universal](https://img.shields.io/badge/universal-arm64%20%7C%20x86__64-555555)](docs/FORMAT_MATRIX.zh-CN.md)
[![本地优先](https://img.shields.io/badge/local--first-no%20media%20upload-2f855a)](PRIVACY.md)
[![源码可见](https://img.shields.io/badge/source-available-8b5cf6)](LICENSE)

File Island 是一款原生、双语的 macOS 图片、视频与音频格式转换工具。它平时隐藏在屏幕顶部或 MacBook 刘海附近；把访达中的文件或普通文件夹拖入 Island 后，即可检查内容、按媒体类型选择参数并在本机完成转换，不会修改源文件。

`DEVELOPMENT_SPEC.md` 是本项目唯一的开发规范与事实来源。

File Island 是**源码可见软件，不是开源软件**。项目自有代码、品牌和原创素材采用 [`LICENSE`](LICENSE) 中的 All Rights Reserved 条款。内置 FFmpeg 独立遵循 LGPL-2.1-or-later，详见 [`Legal/THIRD_PARTY_NOTICES.md`](Legal/THIRD_PARTY_NOTICES.md)。

## 主要能力

- 原生 SwiftUI + AppKit macOS 应用，支持带刘海和无刘海显示器；
- 支持拖入单个文件、多个文件或普通文件夹；
- 文件夹递归扫描会排除隐藏项目、App/Package 和符号链接；
- 图片输入：HEIC、HEIF、JPEG/JPG、PNG、WebP、TIFF、GIF、BMP、AVIF；
- 图片输出：JPEG 或 PNG；
- 视频输入：MOV、MP4、M4V、MKV、WebM、AVI、MPEG、TS、FLV、3GP、WMV；
- 视频输出：高兼容性 H.264/AAC MP4；
- 支持图片最长边、JPEG 质量、元数据移除和单文件目标大小；
- 支持视频 Source、1080p、720p 分辨率上限，以及原生视频的单文件目标大小；
- 音频输入：MP3、WAV、AIFF、M4A/AAC、FLAC、OGG/Opus、AC3；输出 M4A、WAV、FLAC 或 AIFF；
- 支持图片、原生视频、FFmpeg fallback 视频和音频组成的异构文件夹批处理；
- 自动保留文件夹相对结构，并使用防覆盖输出命名；
- 首次转换选择输出文件夹，之后通过安全书签自动复用；
- 转换完全在本机进行，无账号、分析 SDK、广告或媒体上传；
- 提供与 GUI 共用转换核心的结构化 `fileisland` 命令行工具。

## 当前限制

- 需要 macOS 15 或更高版本；
- MP3 支持输入，但暂不提供 MP3 输出；
- WebP 当前仅支持作为输入，不能输出 WebP；
- 暂不支持 RAW、动态图、媒体剪辑、任意自定义码率或自然语言转换命令；
- `v0.2.0` 是 ad-hoc 签名的 early-access 版本，没有 Developer ID 签名，也没有经过 Apple notarization。

## 下载与首次打开

请只从项目的 [GitHub Releases](https://github.com/TREAFREE/FileIsland/releases) 页面下载，并核对同一 Release 中提供的 SHA-256。

`v0.2.0` 没有使用 Apple Developer ID。macOS 通常会阻止第一次启动：

1. 将 File Island 拖入“应用程序”；
2. 尝试打开一次；
3. 打开“系统设置 → 隐私与安全性”；
4. 仅在安装包来自本项目官方 Release 且校验值一致时，选择“仍要打开”。

不要关闭 Gatekeeper。受组织管理的 Mac 可能不允许这一操作。

安装包已经包含 universal arm64/x86_64 App、内置 FFmpeg 和预设文件。普通用户不需要另外安装 Homebrew、FFmpeg、Python、Node.js 或其他运行环境。

## 基本使用

1. 启动 File Island；
2. 把访达中的受支持文件或普通文件夹拖到屏幕顶部的 Island；
3. 检查图片、视频和不支持文件的分组数量；
4. 分别设置图片、视频和音频参数；
5. 点击 **Start**；
6. 第一次使用时选择输出文件夹；
7. 完成后通过 **Show in Finder** 查看结果。

可以在菜单栏图标的 **Settings → General** 中更改输出文件夹。

也可以在 **Settings → General → Language** 中选择跟随系统、English 或简体中文；切换会立即应用到设置窗口、刘海窗口和菜单栏，不会重启正在进行的转换。

## 命令行工具

构建共享的 `FileIslandCLI` scheme 后，产物目录中需要同时存在 `fileisland`、`built-in-presets.json` 和 `ffmpeg`。

```sh
xcodebuild -project FileIsland.xcodeproj \
  -scheme FileIslandCLI \
  -destination 'platform=macOS' \
  -derivedDataPath .build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

查询机器可读的能力矩阵：

```sh
.build/DerivedData/Build/Products/Debug/fileisland capabilities --json
```

递归检查文件夹：

```sh
.build/DerivedData/Build/Products/Debug/fileisland inspect \
  '/path/含 空格的文件夹' --recursive --json
```

转换包含图片、视频与音频的文件夹：

```sh
.build/DerivedData/Build/Products/Debug/fileisland convert \
  '/path/input folder' --recursive \
  --output '/path/output folder' \
  --image-format jpeg --image-max-dimension 2048 --strip-metadata \
  --video-resolution 1080p \
  --audio-format m4a --audio-quality balanced --strip-audio-metadata \
  --json
```

CLI 使用调用者现有的文件系统权限，不读取 GUI 保存的输出文件夹书签。输出目录必须已经存在；源文件不会被覆盖。

## 从源码构建与测试

开发环境：

- macOS 15 或更高版本；
- Xcode 26.1 或更高版本；
- Swift 6。

```sh
xcodebuild -project FileIsland.xcodeproj \
  -scheme FileIsland \
  -destination 'platform=macOS' \
  -derivedDataPath .build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

```sh
xcodebuild -project FileIsland.xcodeproj \
  -scheme FileIsland \
  -destination 'platform=macOS' \
  -derivedDataPath .build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  test
```

## 隐私、安全与许可

- [中文使用教程](docs/USER_GUIDE.zh-CN.md)
- [v0.2 格式矩阵](docs/FORMAT_MATRIX.zh-CN.md)

- [File Island 专有许可](LICENSE)
- [隐私政策](PRIVACY.md)
- [安全报告方式](SECURITY.md)
- [第三方许可声明](Legal/THIRD_PARTY_NOTICES.md)
- [FFmpeg 构建与来源记录](Legal/FFMPEG_BUILD.md)
- [商业化与合规清单](Legal/COMMERCIALIZATION_CHECKLIST.zh-CN.md)
- [DMG 与发行指南](docs/RELEASE_DMG_GUIDE.zh-CN.md)
- [项目概况、进度与后续开发交接](docs/PROJECT_HANDOFF.zh-CN.md)

公开仓库仅用于查看、审计、学习和问题反馈。除 GitHub 服务条款允许的查看与 Fork 外，`LICENSE` 不授予复制、修改、再分发、转售或基于 File Island 自有源码构建其他产品的权利。

## 问题反馈

普通问题请使用 [GitHub Issues](https://github.com/TREAFREE/FileIsland/issues)。未修复的安全漏洞不要发布到公开 Issue，请按照 [`SECURITY.md`](SECURITY.md) 使用私密漏洞报告。
