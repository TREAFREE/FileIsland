#!/bin/sh

set -eu

usage() {
    printf '%s\n' "Usage: $0 <bundled-ffmpeg-path> [split-fixture-path]" >&2
}

fail() {
    printf 'audit_error=%s\n' "$1" >&2
    exit 1
}

boolean() {
    if "$@"; then
        printf '%s' true
    else
        boolean_status=$?
        if [ "$boolean_status" -ne 1 ]; then
            fail "capability inventory could not be parsed"
        fi
        printf '%s' false
    fi
}

has_muxer() {
    muxer_name=$1
    inventory_path=$2

    awk -v wanted="$muxer_name" '
        index($1, "E") > 0 {
            count = split($2, names, ",")
            for (item_index = 1; item_index <= count; item_index += 1) {
                if (names[item_index] == wanted) {
                    found = 1
                }
            }
        }
        END { exit(found ? 0 : 1) }
    ' "$inventory_path"
}

has_any_segment_muxer() {
    inventory_path=$1

    awk '
        index($1, "E") > 0 {
            count = split($2, names, ",")
            for (item_index = 1; item_index <= count; item_index += 1) {
                if (names[item_index] == "segment" ||
                    names[item_index] == "stream_segment" ||
                    names[item_index] == "ssegment") {
                    found = 1
                }
            }
        }
        END { exit(found ? 0 : 1) }
    ' "$inventory_path"
}

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    usage
    exit 64
fi

binary_argument=$1
fixture_argument=${2-}
if printf '%s' "$binary_argument" | LC_ALL=C grep -q '[[:cntrl:]]'; then
    fail "binary path must not contain control characters"
fi

[ -f "$binary_argument" ] || fail "binary does not exist: $binary_argument"
[ -x "$binary_argument" ] || fail "binary is not executable: $binary_argument"
if [ -n "$fixture_argument" ]; then
    if printf '%s' "$fixture_argument" | LC_ALL=C grep -q '[[:cntrl:]]'; then
        fail "fixture path must not contain control characters"
    fi
    [ -f "$fixture_argument" ] || fail "fixture does not exist: $fixture_argument"
    [ -r "$fixture_argument" ] || fail "fixture is not readable: $fixture_argument"
fi

binary_directory=$(CDPATH= cd "$(dirname "$binary_argument")" && pwd -P) ||
    fail "unable to resolve binary directory"
binary_name=$(basename "$binary_argument")
binary_path="$binary_directory/$binary_name"
ffprobe_path="$binary_directory/ffprobe"

audit_directory=$(mktemp -d /tmp/fileisland-ffmpeg-split-audit.XXXXXX) ||
    fail "unable to create audit directory"
trap 'rm -rf "$audit_directory"' EXIT HUP INT TERM

version_output="$audit_directory/version.txt"
muxer_output="$audit_directory/muxers.txt"
filter_output="$audit_directory/filters.txt"
buildconf_output="$audit_directory/buildconf.txt"

"$binary_path" -version >"$version_output" 2>&1 ||
    fail "ffmpeg -version failed"
"$binary_path" -hide_banner -muxers >"$muxer_output" 2>&1 ||
    fail "ffmpeg -muxers failed"
"$binary_path" -hide_banner -filters >"$filter_output" 2>&1 ||
    fail "ffmpeg -filters failed"
"$binary_path" -hide_banner -buildconf >"$buildconf_output" 2>&1 ||
    fail "ffmpeg -buildconf failed"

ffmpeg_version=$(awk '
    NR == 1 && $1 == "ffmpeg" && $2 == "version" { print $3; exit }
' "$version_output")
[ -n "$ffmpeg_version" ] || fail "unable to parse ffmpeg version"

mp4_muxer=$(boolean has_muxer mp4 "$muxer_output")
mov_muxer=$(boolean has_muxer mov "$muxer_output")
segment_muxer=$(boolean has_any_segment_muxer "$muxer_output")

ffprobe=false
ffprobe_version=unavailable
ffprobe_version_matches=false
machine_readable_keyframe_probe=false
keyframe_fixture_probe=false
keyframe_count=0
segment_fixture_smoke=false
if [ -x "$ffprobe_path" ]; then
    ffprobe=true
    ffprobe_version_output="$audit_directory/ffprobe-version.txt"

    "$ffprobe_path" -version >"$ffprobe_version_output" 2>&1 ||
        fail "bundled ffprobe -version failed"
    ffprobe_version=$(awk '
        NR == 1 && $1 == "ffprobe" && $2 == "version" { print $3; exit }
    ' "$ffprobe_version_output")
    [ -n "$ffprobe_version" ] || fail "unable to parse ffprobe version"
    if [ "$ffprobe_version" = "$ffmpeg_version" ]; then
        ffprobe_version_matches=true
    fi

    if [ -n "$fixture_argument" ]; then
        fixture_directory=$(CDPATH= cd "$(dirname "$fixture_argument")" && pwd -P) ||
            fail "unable to resolve fixture directory"
        fixture_path="$fixture_directory/$(basename "$fixture_argument")"
        metadata_output="$audit_directory/fixture-metadata.json"
        keyframe_output="$audit_directory/fixture-keyframes.json"
        keyframe_values="$audit_directory/keyframe-values.txt"

        if "$ffprobe_path" \
            -hide_banner \
            -v error \
            -show_format \
            -show_streams \
            -show_entries \
            'format=format_name,duration,bit_rate:stream=index,codec_type,codec_name,width,height,avg_frame_rate,r_frame_rate,duration,bit_rate,start_time' \
            -of json \
            "$fixture_path" \
            >"$metadata_output" 2>"$audit_directory/fixture-metadata.err" &&
            /usr/bin/plutil -convert xml1 -o /dev/null "$metadata_output" &&
            grep -Eq '"codec_name"[[:space:]]*:[[:space:]]*"h264"' "$metadata_output" &&
            grep -Eq '"codec_name"[[:space:]]*:[[:space:]]*"aac"' "$metadata_output" &&
            "$ffprobe_path" \
                -hide_banner \
                -v error \
                -select_streams v:0 \
                -show_packets \
                -show_entries packet=pts_time,flags \
                -of json \
                "$fixture_path" \
                >"$keyframe_output" 2>"$audit_directory/fixture-keyframes.err" &&
            /usr/bin/plutil -convert xml1 -o /dev/null "$keyframe_output" &&
            awk '
                /"pts_time"[[:space:]]*:/ {
                    value = $0
                    sub(/^[^:]*:[[:space:]]*"/, "", value)
                    sub(/".*$/, "", value)
                    timestamp = value
                }
                /"flags"[[:space:]]*:/ {
                    if (index($0, "K") > 0) {
                        if (timestamp !~ /^-?[0-9]+([.][0-9]+)?$/) exit 2
                        numeric = timestamp + 0
                        if (count == 0 && (numeric < -0.05 || numeric > 0.05)) exit 3
                        if (count > 0 && numeric <= previous) exit 4
                        print timestamp
                        previous = numeric
                        count += 1
                    }
                    timestamp = ""
                }
                END { if (count < 2) exit 5 }
            ' "$keyframe_output" >"$keyframe_values"; then
            keyframe_count=$(awk 'END { print NR + 0 }' "$keyframe_values")
            keyframe_fixture_probe=true
            machine_readable_keyframe_probe=true
        fi

        if [ "$segment_muxer" = true ] && [ "$keyframe_fixture_probe" = true ]; then
            segment_directory="$audit_directory/segments"
            mkdir -p "$segment_directory"
            segment_times=$(awk '
                NR > 1 {
                    if (value != "") value = value ","
                    value = value $0
                }
                END { print value }
            ' "$keyframe_values")
            if [ -n "$segment_times" ] && "$binary_path" \
                -hide_banner \
                -nostdin \
                -v error \
                -y \
                -i "$fixture_path" \
                -map 0:v:0 \
                -map '0:a:0?' \
                -c copy \
                -f segment \
                -segment_format mp4 \
                -segment_times "$segment_times" \
                -segment_time_delta 0.02 \
                -reset_timestamps 1 \
                "$segment_directory/part-%02d.mp4" \
                >"$audit_directory/segment.stdout" \
                2>"$audit_directory/segment.stderr"; then
                segment_count=0
                total_duration=0
                segments_valid=true
                for segment_path in "$segment_directory"/part-*.mp4; do
                    [ -f "$segment_path" ] || continue
                    segment_count=$((segment_count + 1))
                    segment_metadata="$audit_directory/segment-${segment_count}.json"
                    first_packet="$audit_directory/segment-${segment_count}-first-packet.txt"
                    if [ ! -s "$segment_path" ] ||
                        ! "$ffprobe_path" \
                            -hide_banner \
                            -v error \
                            -show_format \
                            -show_streams \
                            -show_entries 'format=duration:stream=codec_type,codec_name' \
                            -of json \
                            "$segment_path" >"$segment_metadata" 2>/dev/null ||
                        ! /usr/bin/plutil -convert xml1 -o /dev/null "$segment_metadata" ||
                        ! grep -Eq '"codec_name"[[:space:]]*:[[:space:]]*"h264"' "$segment_metadata" ||
                        ! grep -Eq '"codec_name"[[:space:]]*:[[:space:]]*"aac"' "$segment_metadata" ||
                        ! "$ffprobe_path" \
                            -hide_banner \
                            -v error \
                            -select_streams v:0 \
                            -read_intervals '%+#1' \
                            -show_packets \
                            -show_entries packet=flags \
                            -of compact=p=0:nk=0 \
                            "$segment_path" >"$first_packet" 2>/dev/null ||
                        ! grep -q 'flags=K' "$first_packet"; then
                        segments_valid=false
                        break
                    fi
                    segment_duration=$("$ffprobe_path" \
                        -v error \
                        -show_entries format=duration \
                        -of default=nw=1:nk=1 \
                        "$segment_path" 2>/dev/null) || segments_valid=false
                    if ! total_duration=$(awk \
                        -v total="$total_duration" \
                        -v duration="$segment_duration" \
                        'BEGIN {
                            if (duration !~ /^[0-9]+([.][0-9]+)?$/) exit 1
                            printf "%.9f", total + duration
                        }'); then
                        segments_valid=false
                        break
                    fi
                done

                source_duration=$("$ffprobe_path" \
                    -v error \
                    -show_entries format=duration \
                    -of default=nw=1:nk=1 \
                    "$fixture_path" 2>/dev/null) || segments_valid=false
                if [ "$segments_valid" = true ] &&
                    [ "$segment_count" -eq "$keyframe_count" ] &&
                    awk -v source="$source_duration" -v total="$total_duration" '
                        BEGIN {
                            difference = source - total
                            if (difference < 0) difference = -difference
                            exit(difference <= 0.5 ? 0 : 1)
                        }
                    '; then
                    segment_fixture_smoke=true
                fi
            fi
        fi
    fi
fi

fast_split_ready=false
if [ "$mp4_muxer" = true ] &&
    [ "$mov_muxer" = true ] &&
    [ "$segment_muxer" = true ] &&
    [ "$ffprobe" = true ] &&
    [ "$ffprobe_version_matches" = true ] &&
    [ "$machine_readable_keyframe_probe" = true ] &&
    [ "$segment_fixture_smoke" = true ]; then
    fast_split_ready=true
fi

printf 'audit_schema_version=2\n'
printf 'audit_complete=true\n'
printf 'binary_path=%s\n' "$binary_argument"
printf 'ffmpeg_version=%s\n' "$ffmpeg_version"
printf 'ffprobe_version=%s\n' "$ffprobe_version"
printf 'ffprobe_version_matches=%s\n' "$ffprobe_version_matches"
printf 'mp4_muxer=%s\n' "$mp4_muxer"
printf 'mov_muxer=%s\n' "$mov_muxer"
printf 'segment_muxer=%s\n' "$segment_muxer"
printf 'ffprobe=%s\n' "$ffprobe"
printf 'machine_readable_keyframe_probe=%s\n' "$machine_readable_keyframe_probe"
printf 'keyframe_fixture_probe=%s\n' "$keyframe_fixture_probe"
printf 'keyframe_count=%s\n' "$keyframe_count"
printf 'segment_fixture_smoke=%s\n' "$segment_fixture_smoke"
printf 'fast_split_ready=%s\n' "$fast_split_ready"
