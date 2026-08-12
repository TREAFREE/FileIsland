# File Island 完整使用教程

[English](USER_GUIDE.md) · [返回项目首页](../README.zh-CN.md) · [查看支持格式](FORMAT_MATRIX.zh-CN.md)

File Island 会把转换工作留在你的 Mac 上。安装包已经包含应用需要的 FFmpeg、ffprobe 和媒体校验工具，不需要另外安装 Homebrew、Python、Node.js 或任何编解码器包。

## 1. 下载并核对安装包

1. 打开项目的 [GitHub Releases](https://github.com/TREAFREE/FileIsland/releases/latest) 页面。
2. 下载最新的 `.dmg` 和同一 Release 中对应的 `.sha256` 文件。
3. 打开“终端”，输入 `shasum -a 256`，在命令后留一个空格，把 DMG 拖进终端，然后按回车。
4. 将显示的校验值与 `.sha256` 文件逐字比较。只有完全一致时才继续。

校验值能帮助确认下载没有损坏或被替换，但当前 ad-hoc 签名版本仍不等同于 Apple Developer ID 身份认证。

## 2. 安装与首次打开

1. 双击 DMG。
2. 把 **File Island.app** 拖到同一窗口中的 **Applications（应用程序）** 快捷方式；不要直接把 DMG 中的 App 当作长期安装版本。
3. 等待复制完成，推出 DMG，然后可以删除下载目录中的 DMG。
4. 从访达的“应用程序”打开 **File Island**。

当前 early-access 版本尚未使用 Apple Developer ID，也没有经过 Apple 公证。第一次打开时 macOS 可能阻止运行：

1. 先正常尝试打开一次；
2. 打开 **系统设置 → 隐私与安全性**；
3. 找到刚才被阻止的 File Island，选择 **仍要打开**；
4. 只有当 DMG 来自本仓库官方 Release 且校验值匹配时才确认。

不要关闭 Gatekeeper。公司或学校管理的 Mac 可能不允许手动放行。

## 3. 图片转换

[![播放图片转换演示](assets/demos/image-conversion.jpg)](assets/demos/image-conversion.mp4)

> 点击封面播放图片批量转换演示。

1. 在访达中选择一张或多张受支持图片，拖到屏幕顶部的 Island。
2. 点击 **Continue（继续）**，在图片组中选择 JPEG 或 PNG。
3. 按需要设置最长边、JPEG 质量、单文件目标大小和是否移除元数据。
4. 点击 **Start（开始）**。
5. 第一次转换时选择一个固定输出文件夹；File Island 会保存这次授权，以后自动使用。
6. 完成后点击 **Show in Finder（在访达中显示）**。

JPEG 适合照片和较小体积；PNG 适合需要透明背景或无损像素的图片。把带透明区域的图片转成 JPEG 时，透明部分会使用白色背景。选择目标大小时，限制针对每个输出文件，而不是整批文件的总和。

## 4. 视频转换与为分享切分

[![播放视频转换与切分演示](assets/demos/video-conversion-and-splitting.jpg)](assets/demos/video-conversion-and-splitting.mp4)

> 点击封面播放普通视频转换和快速切分演示。

### 普通转换

1. 拖入受支持的视频。
2. 选择 **Convert（转换）**。
3. 输出为高兼容性 H.264/AAC MP4。
4. **Source、1080p、720p** 表示画面尺寸上限，不是文件大小。较小的源视频不会被放大。
5. 对原生支持的视频还可设置每个文件的目标体积。为满足严格体积，应用可能降低内部画面尺寸。
6. 点击 **Start** 并等待完成。

### 为分享切分

这个模式适合把长视频拆成多个可单独播放、便于发送的文件。

1. 拖入内部为 H.264 视频、AAC 音轨或无音轨的 MP4/MOV。
2. 选择 **Split for Sharing（为分享切分）**。
3. 设置每段最大体积、最长时长，或同时启用两项。
4. 体积可切换 MB/GB，时长可切换秒/分钟/小时；切换单位不会改变实际限制。
5. 可用滑杆快速选择常见值，也可在精确输入框填写正数。
6. 检查预计片段数并点击 **Start**。

当前快速模式在安全关键帧处直接复制原有编码流，不会主动降低画质。如果源视频关键帧间隔太长，无法严格满足所选大小或时长，File Island 会停止且不发布残缺结果。输出会放在完整的 `视频名 — Split` 文件夹中；重名时自动添加数字后缀。

## 5. 音频转换

[![播放音频转换演示](assets/demos/audio-conversion.jpg)](assets/demos/audio-conversion.mp4)

> 点击封面播放音频批量转换演示。

1. 拖入一个或多个音频文件。
2. 选择 M4A、WAV、FLAC 或 AIFF 输出。
3. 对适用格式选择质量，并决定是否移除音频元数据。
4. 点击 **Start**。

MP3 当前可作为输入，但不提供 MP3 输出。M4A 适合日常播放和较小体积；WAV/AIFF 适合需要 PCM 的工作流；FLAC 适合无损压缩归档。

## 6. 混合文件夹批处理

[![播放混合文件夹演示](assets/demos/mixed-folder.jpg)](assets/demos/mixed-folder.mp4)

> 点击封面播放包含图片、视频和音频的文件夹转换演示。

1. 直接把普通文件夹拖到 Island。
2. File Island 会递归发现媒体，并排除隐藏项目、App/Package 和符号链接。
3. 在顶部切换图片、视频和音频分组；每组只显示适用于该媒体类型的参数。
4. 为每个需要执行的分组完成设置，然后点击一次 **Start**。
5. 输出会保留源文件夹中的相对目录结构。

整批任务使用安全暂存：所有可执行分组成功后才保留最终结果。取消或失败会回滚该批输出；不支持的文件不会被伪装成已转换文件。重名输出使用 `-2`、`-3` 等后缀，源文件永不覆盖。

## 7. 设置、语言和输出文件夹

[![播放设置演示](assets/demos/settings.jpg)](assets/demos/settings.mp4)

> 点击封面播放菜单栏与设置窗口演示。

点击菜单栏中的 File Island 图标，然后选择 **Settings（设置）**：

- **通用**：更改固定输出文件夹、登录时启动、完成后在访达中显示、界面语言；
- **转换**：设置图片默认质量和元数据偏好；
- **外观**：调整 Island 透明度；
- **关于**：查看图标、版本和项目链接。

语言支持跟随系统、English 和简体中文，切换后立即应用，不会中断正在执行的转换。

## 8. 常见问题

### Spotlight 里为什么有多个 File Island？

如果你从 Xcode 构建过项目，Spotlight 可能同时索引正式安装版、Debug/Release 构建和 Xcode 索引副本。这不代表 App 被安装了四次。正式版通常位于 `/Applications/File Island.app`；开发副本位于 `~/Library/Developer/Xcode/DerivedData/`。退出开发版后，可以删除该项目的 DerivedData，再重建 Spotlight 索引结果。

### 看不到 Island

检查菜单栏中是否有 File Island 图标，并确认应用仍在运行。带刘海 Mac 的待机拖放区域位于刘海附近；无刘海显示器使用顶部居中的小胶囊。

### 文件显示不支持

查看[格式矩阵](FORMAT_MATRIX.zh-CN.md)。扩展名匹配不代表内部视频/音频编码一定受支持；File Island 会检查真实媒体流并安全拒绝不符合条件的输入。

### 保存失败

在 **设置 → 通用** 重新选择一个可写输出文件夹，并确认磁盘空间足够。不要把只读 DMG 当作输出位置。

### 如何卸载

1. 从菜单栏菜单退出 File Island。
2. 把“应用程序”中的 **File Island.app** 移到废纸篓。
3. 只有在也希望删除偏好与输出目录授权时，才删除 `~/Library/Containers/com.treafree.FileIsland`。

卸载不会删除源媒体或已经生成的输出文件。

## 9. 问题反馈

可复现问题请使用 [GitHub Issues](https://github.com/TREAFREE/FileIsland/issues)，说明 macOS 版本、File Island 版本、输入格式与操作步骤。请不要把私人媒体上传到公开 Issue。未修复的安全问题请按照[安全政策](../SECURITY.md)私密报告。
