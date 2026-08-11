# File Island 0.3 格式矩阵

[English](FORMAT_MATRIX.md)

本矩阵描述 v0.3.0 Release 的实际能力。

| 媒体 | 已验证输入 | 已验证输出 | 引擎与限制 |
|---|---|---|---|
| 图片 | HEIC、HEIF、JPEG/JPG、PNG、WebP、TIFF、GIF、BMP、AVIF | JPEG、PNG | ImageIO；动态图读取首帧；不宣称支持 WebP 输出 |
| 原生视频 | MOV、MP4、M4V | H.264/AAC MP4 | AVFoundation；支持 Source/1080p/720p 和可选单文件目标大小 |
| 兼容视频 | MKV、WebM、AVI、MPEG/MPG、TS/MTS/M2TS、FLV、3GP、WMV/ASF | H.264/AAC MP4 | 内置 LGPL FFmpeg 8.1.2 + VideoToolbox；不承诺精确字节目标 |
| 音频 | MP3、WAV、AIFF、M4A、AAC、FLAC、OGG/Vorbis、Opus、AC3 | M4A/AAC、WAV/PCM、FLAC、AIFF/PCM | 内置 LGPL FFmpeg 8.1.2；紧凑/均衡/高质量影响 AAC；不宣称支持 MP3 输出 |
| 快速分段分享 | 包含 H.264 视频和可选 AAC 音轨的 MP4 或 MOV | 保留源 H.264 与可选 AAC 编码流的 MP4 或 MOV 分段 | 经审计的内置 FFmpeg + ffprobe；大小支持 MB/GB、时长支持秒/分钟/小时；按关键帧 stream copy，不重新编码；不宣称支持精确模式或平台规则 |

表中每类格式都有提交到仓库的真实 fixture 和解码输出集成测试。损坏文件、容器中不受支持的编码、Package、符号链接和未知格式会保持 fail-closed。File Island 不上传媒体。

快速分段会保留编码后的媒体画质，但只能在安全关键帧处切分。如果现有关键帧无法满足任一已选限制，File Island 会安全失败，而不会超出限制或悄悄重新编码。App 将 `1 MB` 固定解释为 `1,000,000 bytes`、`1 GB` 解释为 `1,000 MB`；切换显示单位不会改变规范化限制。CLI 通过 `--max-bytes` 接收精确字节数。大小与时长限制至少需要填写一项。
