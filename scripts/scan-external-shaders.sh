#!/usr/bin/env bash

set -euo pipefail

shader_dir=${1:?shader directory required}
preview_dir=${2:?preview directory required}
[[ -d "$shader_dir" ]] || exit 0

declare -A previews=()
while IFS= read -r -d '' shader_path; do
    file_name=${shader_path##*/}
    [[ "$file_name" =~ ^([a-z0-9][a-z0-9-]{0,63})_(open|close)\.glsl$ ]] || continue
    base_name=${BASH_REMATCH[1]}
    event_name=${BASH_REMATCH[2]}

    if [[ ! -v "previews[$base_name]" ]]; then
        preview_name=""
        open_path="$shader_dir/${base_name}_open.glsl"
        close_path="$shader_dir/${base_name}_close.glsl"
        if [[ -f "$open_path" && ! -L "$open_path" && -f "$close_path" && ! -L "$close_path" ]]; then
            source_hash=$(cat -- "$open_path" "$close_path" | sha256sum | cut -c1-16)
            candidate="${base_name}-${source_hash}.gif"
            if [[ -f "$preview_dir/$candidate" && ! -L "$preview_dir/$candidate" ]] \
                    && (( $(stat -c %s -- "$preview_dir/$candidate") <= 8388608 )) \
                    && [[ $(head -c 6 -- "$preview_dir/$candidate") == GIF89a ]]; then
                preview_name=$candidate
            fi
        fi
        previews[$base_name]=$preview_name
    fi
    jq -nc --arg base "$base_name" --arg event "$event_name" \
        --arg preview "${previews[$base_name]}" \
        '{base:$base,event:$event,preview:$preview}'
done < <(find "$shader_dir" -maxdepth 1 -type f \
    \( -name '*_open.glsl' -o -name '*_close.glsl' \) -print0)
