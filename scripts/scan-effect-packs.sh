#!/usr/bin/env bash

set -u

declare -a trusted_roots=()
declare -a user_roots=()
settings_json='{}'

emit_error() {
    local manifest_path=$1
    local message=$2
    jq -nc --arg path "$manifest_path" --arg error "$message" \
        '{ok:false,path:$path,error:$error}'
}

is_inside() {
    local child=$1
    local parent=$2
    [[ "$child" == "$parent" || "$child" == "$parent"/* ]]
}

scan_manifest() {
    local manifest_path=$1
    local trusted=$2
    local pack_dir pack_real manifest_size license_path shader_path shader_real
    local preview_path preview_real compile_state compile_output
    local source_format shader_event shader_entry artifact_path artifacts_json
    local common_path common_real duration_seconds scale turbulence fire_color
    local script_dir
    local -a shader_entries=()

    pack_dir=${manifest_path%/effect.json}
    if [[ -L "$manifest_path" || -L "$pack_dir" || ! -f "$manifest_path" ]]; then
        emit_error "$manifest_path" "manifest and pack directory must be regular, non-symlinked paths"
        return
    fi
    manifest_size=$(stat -c %s -- "$manifest_path" 2>/dev/null || printf '0')
    if (( manifest_size <= 0 || manifest_size > 131072 )); then
        emit_error "$manifest_path" "effect.json exceeds the 128 KiB limit or is empty"
        return
    fi
    if ! jq -e 'type == "object"' "$manifest_path" >/dev/null 2>&1; then
        emit_error "$manifest_path" "effect.json is not valid JSON object"
        return
    fi

    pack_real=$(realpath -e -- "$pack_dir" 2>/dev/null) || {
        emit_error "$manifest_path" "pack directory cannot be resolved"
        return
    }
    license_path="$pack_dir/LICENSE"
    if [[ -L "$license_path" || ! -f "$license_path" ]]; then
        emit_error "$manifest_path" "regular LICENSE file is required"
        return
    fi

    source_format=$(jq -r '.compatibility.sourceFormat // empty' "$manifest_path")
    if [[ "$source_format" != native && "$source_format" != niri \
            && "$source_format" != bmw ]]; then
        emit_error "$manifest_path" "scanner supports native, Niri, and pinned BMW Incinerate source formats only"
        return
    fi
    if [[ "$source_format" == bmw ]]; then
        if [[ $(jq -r '.id // empty' "$manifest_path") != bmw/incinerate ]]; then
            emit_error "$manifest_path" "BMW V1 supports the pinned Incinerate pack only"
            return
        fi
        common_path="$pack_dir/common.glsl"
        if [[ -L "$common_path" || ! -f "$common_path" ]]; then
            emit_error "$manifest_path" "BMW common.glsl must be a regular, non-symlinked file"
            return
        fi
        common_real=$(realpath -e -- "$common_path" 2>/dev/null) || {
            emit_error "$manifest_path" "BMW common.glsl cannot be resolved"
            return
        }
        if ! is_inside "$common_real" "$pack_real" \
                || (( $(stat -c %s -- "$common_real") > 524288 )); then
            emit_error "$manifest_path" "BMW common.glsl escapes the pack or exceeds 512 KiB"
            return
        fi
        scale=$(jq -r --arg id 'bmw/incinerate' '.parameters[$id].scale // empty' <<< "$settings_json")
        turbulence=$(jq -r --arg id 'bmw/incinerate' '.parameters[$id].turbulence // empty' <<< "$settings_json")
        fire_color=$(jq -r --arg id 'bmw/incinerate' '.parameters[$id].color // empty' <<< "$settings_json")
        [[ -n "$scale" ]] || scale=$(jq -r '.parameters[]? | select(.id == "scale") | .default' "$manifest_path")
        [[ -n "$turbulence" ]] || turbulence=$(jq -r '.parameters[]? | select(.id == "turbulence") | .default' "$manifest_path")
        [[ -n "$fire_color" ]] || fire_color=$(jq -r '.parameters[]? | select(.id == "color") | .default' "$manifest_path")
    fi
    mapfile -t shader_entries < <(jq -r '
        if (.shaders | type) == "object" then .shaders | to_entries[] | [.key, .value] | @tsv else empty end
    ' "$manifest_path")
    if (( ${#shader_entries[@]} == 0 )); then
        emit_error "$manifest_path" "at least one shader is required"
        return
    fi
    compile_state=validated
    artifacts_json='{}'
    script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
    for shader_entry in "${shader_entries[@]}"; do
        shader_event=${shader_entry%%$'\t'*}
        shader_path=${shader_entry#*$'\t'}
        if [[ ! "$shader_path" =~ ^[A-Za-z0-9._/-]+$ || "$shader_path" == /* \
                || "$shader_path" == *\\* || "/$shader_path/" == *"/../"* \
                || "/$shader_path/" == *"/./"* ]]; then
            emit_error "$manifest_path" "shader path is not a safe pack-relative path: $shader_path"
            return
        fi
        if [[ -L "$pack_dir/$shader_path" || ! -f "$pack_dir/$shader_path" ]]; then
            emit_error "$manifest_path" "shader must be a regular, non-symlinked file: $shader_path"
            return
        fi
        shader_real=$(realpath -e -- "$pack_dir/$shader_path" 2>/dev/null) || {
            emit_error "$manifest_path" "shader cannot be resolved: $shader_path"
            return
        }
        if ! is_inside "$shader_real" "$pack_real"; then
            emit_error "$manifest_path" "shader escapes pack directory: $shader_path"
            return
        fi
        if (( $(stat -c %s -- "$shader_real") > 524288 )); then
            emit_error "$manifest_path" "shader exceeds the 512 KiB limit: $shader_path"
            return
        fi
        if grep -Eq '^[[:space:]]*#[[:space:]]*include\b' "$shader_real"; then
            emit_error "$manifest_path" "E2 executable packs require self-contained shaders: $shader_path"
            return
        fi
        if [[ "$source_format" == niri || "$source_format" == bmw ]]; then
            if [[ "$shader_event" != open && "$shader_event" != close ]]; then
                emit_error "$manifest_path" "source adapter supports open and close only"
                return
            fi
            if [[ "$source_format" == niri ]]; then
                if ! artifact_path=$("$script_dir/compile-niri-shader.sh" "$shader_real" "$shader_event" 2>&1); then
                    emit_error "$manifest_path" "Niri adaptation failed for $shader_path: ${artifact_path:0:1024}"
                    return
                fi
            else
                duration_seconds=$(jq -r --arg event "$shader_event" \
                    '.timings[$event] // empty' <<< "$settings_json")
                [[ -n "$duration_seconds" ]] || duration_seconds=$(jq -r '.duration.defaultMs / 1000' "$manifest_path")
                if ! artifact_path=$("$script_dir/compile-bmw-incinerate.sh" \
                        "$shader_real" "$common_real" "$shader_event" \
                        "$duration_seconds" "$scale" "$turbulence" "$fire_color" 2>&1); then
                    emit_error "$manifest_path" "BMW adaptation failed for $shader_path: ${artifact_path:0:1024}"
                    return
                fi
            fi
            artifacts_json=$(jq -nc --argjson current "$artifacts_json" \
                --arg event "$shader_event" --arg path "$artifact_path" \
                '$current + {($event): $path}')
        else
            if command -v glslangValidator >/dev/null 2>&1; then
                if ! compile_output=$(glslangValidator -S frag "$shader_real" 2>&1); then
                    emit_error "$manifest_path" "shader compilation failed for $shader_path: ${compile_output//$'\n'/ }"
                    return
                fi
            elif [[ "$trusted" == true ]]; then
                compile_state=release-validated
            else
                emit_error "$manifest_path" "glslangValidator is required for user-installed packs"
                return
            fi
        fi
    done

    preview_path=$(jq -r '.preview // empty' "$manifest_path")
    if [[ -n "$preview_path" ]]; then
        if [[ ! "$preview_path" =~ ^[A-Za-z0-9._/-]+$ || "$preview_path" == /* \
                || "/$preview_path/" == *"/../"* || -L "$pack_dir/$preview_path" \
                || ! -f "$pack_dir/$preview_path" ]]; then
            emit_error "$manifest_path" "preview must be a regular pack-relative file"
            return
        fi
        preview_real=$(realpath -e -- "$pack_dir/$preview_path" 2>/dev/null) || {
            emit_error "$manifest_path" "preview cannot be resolved"
            return
        }
        if ! is_inside "$preview_real" "$pack_real"; then
            emit_error "$manifest_path" "preview escapes pack directory"
            return
        fi
        if [[ ! "$preview_real" =~ \.(png|jpg|jpeg|webp|gif)$ ]] \
                || (( $(stat -c %s -- "$preview_real") > 8388608 )); then
            emit_error "$manifest_path" "preview must be an image no larger than 8 MiB"
            return
        fi
    fi

    jq -c --arg root "$pack_real" --arg compilation "$compile_state" \
        --argjson artifacts "$artifacts_json" \
        '{ok:true,root:$root,compilation:$compilation,artifacts:$artifacts,manifest:.}' "$manifest_path"
}

while (( $# > 0 )); do
    case "$1" in
        --trusted-root)
            [[ $# -ge 2 ]] || { printf '%s\n' 'missing value for --trusted-root' >&2; exit 2; }
            trusted_roots+=("$2")
            shift 2
            ;;
        --root)
            [[ $# -ge 2 ]] || { printf '%s\n' 'missing value for --root' >&2; exit 2; }
            user_roots+=("$2")
            shift 2
            ;;
        --settings-json)
            [[ $# -ge 2 ]] || { printf '%s\n' 'missing value for --settings-json' >&2; exit 2; }
            settings_json=$2
            if (( ${#settings_json} > 16384 )) \
                    || ! jq -e 'type == "object" and (.parameters // {} | type == "object")
                        and (.timings // {} | type == "object")' \
                        <<< "$settings_json" >/dev/null 2>&1; then
                printf '%s\n' 'settings JSON is invalid or too large' >&2
                exit 2
            fi
            shift 2
            ;;
        *)
            printf 'unknown argument: %s\n' "$1" >&2
            exit 2
            ;;
    esac
done

for root in "${trusted_roots[@]}"; do
    [[ -d "$root" && ! -L "$root" ]] || continue
    while IFS= read -r manifest_path; do scan_manifest "$manifest_path" true; done \
        < <(find "$root" -mindepth 2 -maxdepth 4 -type f -name effect.json -print | sort)
done

for root in "${user_roots[@]}"; do
    [[ -d "$root" && ! -L "$root" ]] || continue
    while IFS= read -r manifest_path; do scan_manifest "$manifest_path" false; done \
        < <(find "$root" -mindepth 2 -maxdepth 4 -type f -name effect.json -print | sort)
done
