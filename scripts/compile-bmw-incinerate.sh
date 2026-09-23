#!/usr/bin/env bash

set -euo pipefail

if (( $# < 3 || $# > 7 )); then
    printf '%s\n' 'usage: compile-bmw-incinerate.sh <incinerate.frag> <common.glsl> <open|close> [duration-sec] [scale] [turbulence] [#rrggbb]' >&2
    exit 2
fi

source_path=$1
common_path=$2
event_name=$3
duration=${4:-2.0}
scale=${5:-1.0}
turbulence=${6:-0.3}
fire_color=${7:-'#ffb47f'}

case "$event_name" in
    open|close) ;;
    *) printf '%s\n' 'BMW Incinerate supports open and close only' >&2; exit 2 ;;
esac
for source_file in "$source_path" "$common_path"; do
    if [[ -L "$source_file" || ! -f "$source_file" ]]; then
        printf '%s\n' 'BMW source must be a regular non-symlinked file' >&2
        exit 1
    fi
done
if [[ $(sha256sum "$source_path" | awk '{print $1}') != a398ba215e44f1c61b6a311c47646f84915453f470890dd6840a1c2a28063af9 \
        || $(sha256sum "$common_path" | awk '{print $1}') != 35dd19b584d190a169b5261efc43d7698703a690e414d9c6527fb0e79f4c8b31 ]]; then
    printf '%s\n' 'BMW Incinerate source differs from the pinned upstream revision' >&2
    exit 1
fi
if ! command -v glslangValidator >/dev/null 2>&1; then
    printf '%s\n' 'glslangValidator is required for BMW adaptation' >&2
    exit 1
fi

valid_number() {
    local value=$1 lower=$2 upper=$3
    [[ "$value" =~ ^[0-9]+(\.[0-9]{1,4})?$ ]] \
        && awk -v n="$value" -v lo="$lower" -v hi="$upper" \
            'BEGIN { exit !(n >= lo && n <= hi) }'
}
if ! valid_number "$duration" 0.1 5.0 \
        || ! valid_number "$scale" 0.1 3.0 \
        || ! valid_number "$turbulence" 0.0 1.0 \
        || [[ ! "$fire_color" =~ ^\#[0-9A-Fa-f]{6}$ ]]; then
    printf '%s\n' 'BMW Incinerate parameters are invalid or out of range' >&2
    exit 2
fi
[[ "$duration" == *.* ]] || duration+=.0
[[ "$scale" == *.* ]] || scale+=.0
[[ "$turbulence" == *.* ]] || turbulence+=.0

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
prelude_path="$script_dir/../effects/compat/bmw/prelude.glslinc"
main_path="$script_dir/../effects/compat/bmw/main.glslinc"
cache_home=${XDG_CACHE_HOME:-"$HOME/.cache"}
cache_dir="$cache_home/omadecor/effects/bmw-incinerate-v1"
if [[ -L "$cache_home/omadecor" || -L "$cache_home/omadecor/effects" \
        || -L "$cache_dir" ]]; then
    printf '%s\n' 'refusing symlinked BMW artifact cache directory' >&2
    exit 1
fi
mkdir -p -- "$cache_dir"

digest=$({
    sha256sum "$source_path" "$common_path" "$prelude_path" "$main_path"
    printf '%s\n' "$event_name" "$duration" "$scale" "$turbulence" "$fire_color"
} | sha256sum | awk '{print $1}')
artifact_path="$cache_dir/${digest}-${event_name}.glsl"
if [[ -L "$artifact_path" || ( -e "$artifact_path" && ! -f "$artifact_path" ) ]]; then
    printf '%s\n' 'refusing non-regular BMW artifact target' >&2
    exit 1
fi

temporary_path=$(mktemp "$cache_dir/.bmw.XXXXXXXX.glsl")
trap 'rm -f -- "$temporary_path"' EXIT

color_r=$((16#${fire_color:1:2}))
color_g=$((16#${fire_color:3:2}))
color_b=$((16#${fire_color:5:2}))
{
    sed -n '1,$p' "$prelude_path"
    if [[ "$event_name" == open ]]; then
        printf '%s\n' '#define BMW_OPENING true'
    else
        printf '%s\n' '#define BMW_OPENING false'
    fi
    printf 'const float uDuration = %s;\n' "$duration"
    printf 'const float uScale = %s;\n' "$scale"
    printf 'const float uTurbulence = %s;\n' "$turbulence"
    printf 'const vec3 uColor = vec3(%d.0, %d.0, %d.0) / 255.0;\n' \
        "$color_r" "$color_g" "$color_b"
    printf '%s\n' '// BMW common.glsl, GPL-3.0-or-later; original notices follow.'
    sed -n '1,17p' "$common_path"
    awk '/^#endif  \/\/ -+$/ { body = 1; next } body { print }' "$common_path"
    sed -E \
        -e '/^uniform (vec2 uSeed|vec3 uColor|float uScale|float uTurbulence|vec2 uStartPos);$/d' \
        -e 's/^void main\(\) \{/void bmw_main() {/' \
        "$source_path"
    sed -n '1,$p' "$main_path"
} > "$temporary_path"

if ! compile_output=$(glslangValidator -S frag "$temporary_path" 2>&1); then
    printf 'BMW Incinerate compilation failed: %s\n' "${compile_output//$'\n'/ }" >&2
    exit 1
fi
if [[ ! -f "$artifact_path" ]] || ! cmp -s -- "$temporary_path" "$artifact_path"; then
    chmod 0644 "$temporary_path"
    mv -f -- "$temporary_path" "$artifact_path"
fi
printf '%s\n' "$artifact_path"
