#!/usr/bin/env bash

set -euo pipefail

if (( $# != 2 )); then
    printf '%s\n' 'usage: compile-niri-shader.sh <source.glsl> <open|close>' >&2
    exit 2
fi

source_path=$1
event_name=$2
case "$event_name" in
    open|close) ;;
    *) printf '%s\n' 'Niri V1 supports open and close only' >&2; exit 2 ;;
esac

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
adapter_dir="$script_dir/../effects/compat/niri"
prelude_path="$adapter_dir/prelude.glslinc"
main_path="$adapter_dir/main.glslinc"
if [[ -L "$source_path" || ! -f "$source_path" ]]; then
    printf '%s\n' 'Niri source must be a regular non-symlinked file' >&2
    exit 1
fi
if ! command -v glslangValidator >/dev/null 2>&1; then
    printf '%s\n' 'glslangValidator is required for Niri compatibility' >&2
    exit 1
fi

# Niri's interface is unstable: accept only the documented open/close subset.
if grep -Eq '^[[:space:]]*#|\b(uniform|layout|void[[:space:]]+main)[[:space:](]' "$source_path"; then
    printf '%s\n' 'Niri source contains unsupported directives or shader declarations' >&2
    exit 1
fi
if ! grep -Eq "vec4[[:space:]]+${event_name}_color[[:space:]]*\\(" "$source_path"; then
    printf '%s\n' "Niri source is missing ${event_name}_color" >&2
    exit 1
fi
while IFS= read -r symbol; do
    case "$symbol" in
        niri_clamped_progress|niri_random_seed|niri_tex|niri_geo_to_tex) ;;
        *) printf 'unsupported Niri symbol: %s\n' "$symbol" >&2; exit 1 ;;
    esac
done < <(grep -oE 'niri_[[:alnum:]_]+' "$source_path" | sort -u || true)

cache_home=${XDG_CACHE_HOME:-"$HOME/.cache"}
cache_dir="$cache_home/omadecor/effects/niri-v1"
if [[ -L "$cache_home/omadecor" || -L "$cache_home/omadecor/effects"
        || -L "$cache_dir" ]]; then
    printf '%s\n' 'refusing symlinked Niri artifact cache directory' >&2
    exit 1
fi
mkdir -p -- "$cache_dir"
digest=$(sha256sum "$source_path" "$prelude_path" "$main_path" \
    | awk '{print $1}' | sha256sum | awk '{print $1}')
artifact_path="$cache_dir/${digest}-${event_name}.glsl"
if [[ -L "$artifact_path" || ( -e "$artifact_path" && ! -f "$artifact_path" ) ]]; then
    printf '%s\n' 'refusing non-regular Niri artifact target' >&2
    exit 1
fi

temporary_path=$(mktemp "$cache_dir/.niri.XXXXXXXX.glsl")
trap 'rm -f -- "$temporary_path"' EXIT
{
    sed -n '1,$p' "$prelude_path"
    printf '\n#define NIRI_ENTRY %s_color\n' "$event_name"
    sed -n '1,$p' "$source_path"
    sed -n '1,$p' "$main_path"
} > "$temporary_path"

if ! compile_output=$(glslangValidator -S frag "$temporary_path" 2>&1); then
    printf 'Niri shader compilation failed: %s\n' "${compile_output//$'\n'/ }" >&2
    exit 1
fi
if [[ ! -f "$artifact_path" ]] || ! cmp -s -- "$temporary_path" "$artifact_path"; then
    chmod 0644 "$temporary_path"
    mv -f -- "$temporary_path" "$artifact_path"
fi
printf '%s\n' "$artifact_path"
