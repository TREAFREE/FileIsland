#!/bin/sh

set -eu

script_directory=$(CDPATH= cd "$(dirname "$0")" && pwd -P)
project_directory=$(CDPATH= cd "$script_directory/.." && pwd -P)
ffmpeg_path=${1:-"$project_directory/Vendor/FFmpeg/ffmpeg"}
source_path="$project_directory/FileIslandTests/Fixtures/task007-landscape.mkv"
output_path="$project_directory/FileIslandTests/Fixtures/task016-keyframes.mp4"

[ -x "$ffmpeg_path" ] || {
    printf 'error: FFmpeg is not executable: %s\n' "$ffmpeg_path" >&2
    exit 1
}
[ -f "$source_path" ] || {
    printf 'error: source fixture is missing: %s\n' "$source_path" >&2
    exit 1
}

temporary_directory=$(mktemp -d /private/tmp/fileisland-task016-fixture.XXXXXX)
trap 'rm -rf "$temporary_directory"' EXIT HUP INT TERM
temporary_output="$temporary_directory/task016-keyframes.mp4"

"$ffmpeg_path" \
    -hide_banner \
    -nostdin \
    -y \
    -stream_loop 4 \
    -i "$source_path" \
    -t 4 \
    -map 0:v:0 \
    -map 0:a:0 \
    -c copy \
    -map_metadata -1 \
    -metadata title="File Island Task 016 Fixture" \
    -metadata comment="Must be removed by strip-metadata split" \
    -movflags +faststart \
    "$temporary_output"

[ -s "$temporary_output" ] || {
    printf 'error: generated fixture is empty\n' >&2
    exit 1
}

mv "$temporary_output" "$output_path"
printf 'Generated %s\n' "$output_path"
