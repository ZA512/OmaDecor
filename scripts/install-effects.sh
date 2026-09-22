#!/usr/bin/env bash

set -euo pipefail

engine_url="https://github.com/ManofJELLO/HyprWindowShade"
pack_url="https://github.com/jbuck95/Hyprland-Shader.git"
data_root="${XDG_DATA_HOME:-${HOME}/.local/share}"
pack_root="${data_root}/omadecor/shader-packs/hyprland-shader"

finish() {
    printf '\nPress Enter to close this terminal.'
    read -r _
}

trap finish EXIT

printf '%s\n' \
    'OmaDecor effects installer' \
    '' \
    'This installs two external projects:' \
    '  1. HyprWindowShade through hyprpm (native Hyprland plugin).' \
    '  2. Hyprland-Shader in your user data directory (55 open/close pairs).' \
    '' \
    'hyprpm may request your password to manage its cache.' \
    'No file under /usr/share/omarchy will be modified.' \
    ''

read -r -p 'Continue? [y/N] ' answer
case "${answer}" in
    y|Y|yes|YES) ;;
    *) printf '%s\n' 'Cancelled.'; exit 0 ;;
esac

engine_known=false
for state_file in /var/cache/hyprpm/state.toml "${data_root}/hyprpm/state.toml"; do
    if [[ -r "${state_file}" ]] && grep -qi 'HyprWindowShade' "${state_file}"; then
        engine_known=true
    fi
done

if [[ "${engine_known}" == true ]]; then
    printf '\n%s\n' 'HyprWindowShade is already registered with hyprpm.'
else
    printf '\n%s\n' 'Installing HyprWindowShade...'
    hyprpm add "${engine_url}"
fi

hyprpm enable HyprWindowShade
hyprpm reload -n

printf '\n%s\n' 'Installing the external shader pack...'
if [[ -L "${pack_root}" ]]; then
    printf '%s\n' "Refusing symlinked destination: ${pack_root}" >&2
    exit 1
elif [[ -d "${pack_root}/.git" ]]; then
    git -C "${pack_root}" pull --ff-only
elif [[ -e "${pack_root}" ]]; then
    printf '%s\n' "Destination exists but is not a Git checkout: ${pack_root}" >&2
    exit 1
else
    mkdir -p "${pack_root%/*}"
    git clone --depth 1 "${pack_url}" "${pack_root}"
fi

printf '%s\n' \
    '' \
    'Installation complete.' \
    'Return to OD → Effects and click “Check again”.' \
    'The external pack remains separately licensed; see its LICENSE file.'
