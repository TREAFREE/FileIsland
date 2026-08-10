# File Island 0.2 格式矩阵

[English](FORMAT_MATRIX.md)

| 媒体 | 已验证输入 | 已验证输出 | 引擎与限制 |
|---|---|---|---|
| 图片 | HEIC、HEIF、JPEG/JPG、PNG、WebP、TIFF、GIF、BMP、AVIF | JPEG、PNG | ImageIO；动态图读取首帧；不宣称支持 WebP 输出 |
| 原生视频 | MOV、MP4、M4V | H.264/AAC MP4 | AVFoundation；支持 Source/1080p/720p 和可选单文件目标大小 |
| 兼容视频 | MKV、WebM、AVI、MPEG/MPG、TS/MTS/M2TS、FLV、3GP、WMV/ASF | H.264/AAC MP4 | 内置 LGPL FFmpeg 8.1.2 + VideoToolbox；不承诺精确字节目标 |
| 音频 | MP3、WAV、AIFF、M4A、AAC、FLAC、OGG/Vorbis、Opus、AC3 | M4A/AAC、WAV/PCM、FLAC、AIFF/PCM | 内置 LGPL FFmpeg 8.1.2；紧凑/均衡/高质量影响 AAC；不宣称支持 MP3 输出 |

表中每类格式都有提交到仓库的真实 fixture 和解码输出集成测试。损坏文件、容器中不受支持的编码、Package、符号链接和未知格式会保持 fail-closed。File Island 不上传媒体。
