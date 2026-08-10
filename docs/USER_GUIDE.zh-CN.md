# File Island 使用教程

[English](USER_GUIDE.md)

## 安装与首次打开

1. 从官方 GitHub Release 下载 DMG 和对应的 SHA-256 文件。
2. 执行 `shasum -a 256 FileIsland-0.2.0-unsigned.dmg` 并核对校验值。
3. 打开 DMG，把 **File Island.app** 拖到 **Applications（应用程序）** 快捷方式上。
4. 从“应用程序”启动。当前版本未使用 Developer ID，首次尝试打开后可能需要到 **系统设置 → 隐私与安全性 → 仍要打开**。不要关闭 Gatekeeper。

DMG 已包含 universal App 和经审计的 FFmpeg，不需要另装 Homebrew 或 FFmpeg。

## 转换文件

1. 把一个或多个受支持文件，或普通文件夹，拖到当前屏幕顶部的 Island。
2. 检查媒体分组；图片、视频和音频分别显示适用参数。
3. 选择输出格式。MP3 可作为输入，但出于编码器与合规边界暂不提供 MP3 输出。
4. 点击 **Start**。首次使用时授权一个固定输出文件夹；之后可在 **设置 → 通用** 中更改。
5. 等待进度完成，然后在访达中查看结果。

源文件不会被覆盖；文件夹结构会保留；重名输出自动增加数字后缀；失败或取消会回滚整个批次。

## 语言与自动化

在 **设置 → 通用 → 语言** 选择跟随系统、English 或简体中文，界面会立即切换。

脚本或 Agent 可构建 `FileIslandCLI` scheme，并先调用 `fileisland capabilities --json` 获取真实能力。CLI 使用显式路径和调用者权限，不会读取 GUI 保存的输出文件夹书签。示例见主 README。

## 排查问题

- 看不到 Island 时，先确认菜单栏中有 File Island 图标且应用仍在运行。
- 文件被阻止时，请查看[格式矩阵](FORMAT_MATRIX.zh-CN.md)；扩展名正确不代表内部媒体流一定可解码。
- 保存失败时，在设置中选择可写目录并确认磁盘空间充足。
- 可复现问题请通过 GitHub Issues 反馈，不要上传隐私媒体。
