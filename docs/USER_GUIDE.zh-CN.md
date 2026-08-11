# File Island 使用教程

[English](USER_GUIDE.md)

## 安装与首次打开

1. 从官方 GitHub Release 下载 DMG 和对应的 SHA-256 文件。
2. 执行 `shasum -a 256 FileIsland-0.3.0-unsigned.dmg`，并与同一 Release 附带的校验文件核对。
3. 打开 DMG，把 **File Island.app** 拖到 **Applications（应用程序）** 快捷方式上。
4. 从“应用程序”启动。当前版本未使用 Developer ID，首次尝试打开后可能需要到 **系统设置 → 隐私与安全性 → 仍要打开**。不要关闭 Gatekeeper。

DMG 已包含 universal App 和经审计的 FFmpeg/ffprobe，不需要另装 Homebrew 或任何 FFmpeg 工具。

## 转换文件

1. 把一个或多个受支持文件，或普通文件夹，拖到当前屏幕顶部的 Island。
2. 检查媒体分组；图片、视频和音频分别显示适用参数。
3. 选择输出格式。MP3 可作为输入，但出于编码器与合规边界暂不提供 MP3 输出。
4. 点击 **Start**。首次使用时授权一个固定输出文件夹；之后可在 **设置 → 通用** 中更改。
5. 等待进度完成，然后在访达中查看结果。

源文件不会被覆盖；文件夹结构会保留；重名输出自动增加数字后缀；失败或取消会回滚整个批次。

## 为分享切分视频

如果 MP4 或 MOV 内部是 H.264 视频，并带有 AAC 音轨或没有音轨：

1. 把视频拖入 Island，在视频操作中选择 **为分享切分**，而不是“转换”。
2. 使用滑杆或精确输入框设置正数的最大体积、最大时长或同时设置两项。大小可选择 MB/GB，时长可选择秒/分钟/小时；切换单位不会改变实际限制。
3. 检查预计片段数，然后点击 **Start**。
4. File Island 会一次性发布完整的 `电影名 — Split` 文件夹；若重名则使用 `Split-2`。

首个切分模式会在安全关键帧处直接复制原编码流，因此不会主动降低画质。如果现有关键帧无法满足限制，任务会安全失败。精确重编码模式以及针对微信等具体平台的已核验规则尚未实现。

## 语言与自动化

在 **设置 → 通用 → 语言** 选择跟随系统、English 或简体中文，界面会立即切换。

脚本或 Agent 可构建 `FileIslandCLI` scheme，并先调用 `fileisland capabilities --json` 获取真实能力。CLI 使用显式路径和调用者权限，不会读取 GUI 保存的输出文件夹书签；`fileisland split` 支持同一套 Custom 快速关键帧模式。示例见主 README。

## 排查问题

- 看不到 Island 时，先确认菜单栏中有 File Island 图标且应用仍在运行。
- 文件被阻止时，请查看[格式矩阵](FORMAT_MATRIX.zh-CN.md)；扩展名正确不代表内部媒体流一定可解码。
- 保存失败时，在设置中选择可写目录并确认磁盘空间充足。
- 可复现问题请通过 GitHub Issues 反馈，不要上传隐私媒体。

## 卸载

1. 从菜单栏菜单退出 File Island。
2. 将“应用程序”中的 **File Island.app** 移到废纸篓。
3. 可选：只有在也希望删除已保存的输出目录授权和偏好时，才删除 `~/Library/Containers/com.treafree.FileIsland` 沙盒容器。

卸载 File Island 不会删除源媒体或之前已经生成的输出文件。
