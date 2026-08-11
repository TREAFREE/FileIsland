# Third-Party Notices

## FFmpeg 8.1.2

File Island includes `ffmpeg` and `ffprobe` executables built from the same unmodified FFmpeg 8.1.2 source. They run as separate local processes for audited media conversion, metadata/keyframe inspection, and local stream-copy segmentation; they are not linked into File Island.

FFmpeg is licensed under the GNU Lesser General Public License, version 2.1 or later. This project build enables FFmpeg's LGPL `ffprobe` program and generic segment muxer, but does not enable `--enable-gpl`, `--enable-nonfree`, libx264, libx265, or another external codec library. Network support remains disabled.

- Project: https://ffmpeg.org/
- Source: https://ffmpeg.org/releases/ffmpeg-8.1.2.tar.xz
- Corresponding source archive: `Legal/source/ffmpeg-8.1.2.tar.xz`
- Detached signature: `Legal/signatures/ffmpeg-8.1.2.tar.xz.asc`
- Release signing key: `Legal/signatures/ffmpeg-devel.asc`
- License text: `Legal/licenses/COPYING.LGPLv2.1`
- Reproduction instructions: `Legal/FFMPEG_BUILD.md`

FFmpeg is a trademark of Fabrice Bellard, originator of the FFmpeg project. File Island is not affiliated with or endorsed by the FFmpeg project.

The FFmpeg software license and codec patent considerations are separate matters. This notice records dependency provenance and build configuration; it is not legal advice or a conclusion about patent rights in any jurisdiction.
