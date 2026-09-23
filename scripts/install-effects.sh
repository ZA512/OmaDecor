#!/usr/bin/env bash

set -euo pipefail

engine_url="https://github.com/ManofJELLO/HyprWindowShade"
pack_url="https://github.com/jbuck95/Hyprland-Shader.git"
data_root="${XDG_DATA_HOME:-${HOME}/.local/share}"
pack_root="${data_root}/omadecor/shader-packs/hyprland-shader"
hyprpm_log=""

finish() {
    if [[ -n "${hyprpm_log}" ]]; then
        rm -f -- "${hyprpm_log}"
    fi
    printf '\nPress Enter to close this terminal.'
    read -r _ || true
}

trap finish EXIT

engine_registered() {
    local state_file

    for state_file in /var/cache/hyprpm/state.toml "${data_root}/hyprpm/state.toml"; do
        if [[ -r "${state_file}" ]] && grep -qi 'HyprWindowShade' "${state_file}"; then
            return 0
        fi
    done

    return 1
}

ensure_supported_hyprland() {
    local version_json
    local version

    if ! command -v hyprctl >/dev/null 2>&1; then
        printf '\n%s\n' 'Hyprland is required, but hyprctl was not found.' >&2
        return 1
    fi

    if ! version_json="$(hyprctl version -j 2>/dev/null)"; then
        printf '\n%s\n' 'Unable to query the running Hyprland version.' >&2
        return 1
    fi

    if [[ ! "${version_json}" =~ \"version\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
        printf '\n%s\n' 'Unable to parse the running Hyprland version.' >&2
        return 1
    fi
    version="${BASH_REMATCH[1]}"

    case "${version}" in
        0.56|0.56.*)
            printf '\nDetected supported Hyprland %s.\n' "${version}"
            ;;
        *)
            printf '\nUnsupported Hyprland version: %s\n' "${version}" >&2
            printf '%s\n' \
                'This OmaDecor release and HyprWindowShade currently target Hyprland 0.56.x.' \
                'Use an OmaDecor release validated for your Omarchy/Hyprland version.' >&2
            return 1
            ;;
    esac
}

ensure_build_dependencies() {
    local dependency
    local command_name
    local missing_package
    local package_name
    local package_present
    local -a missing_packages=()
    local -a dependencies=(
        'cmake:cmake'
        'cpio:cpio'
        'pkg-config:pkgconf'
        'git:git'
        'g++:gcc'
        'gcc:gcc'
        'make:make'
    )

    for dependency in "${dependencies[@]}"; do
        command_name="${dependency%%:*}"
        package_name="${dependency#*:}"
        if command -v "${command_name}" >/dev/null 2>&1; then
            continue
        fi

        package_present=false
        for missing_package in "${missing_packages[@]}"; do
            if [[ "${missing_package}" == "${package_name}" ]]; then
                package_present=true
                break
            fi
        done
        if [[ "${package_present}" == false ]]; then
            missing_packages+=("${package_name}")
        fi
    done

    if (( ${#missing_packages[@]} == 0 )); then
        return 0
    fi

    if ! command -v omarchy >/dev/null 2>&1; then
        printf '\nMissing build packages: %s\n' "${missing_packages[*]}" >&2
        printf '%s\n' 'Install them with your system package manager, then retry.' >&2
        return 1
    fi

    printf '\nMissing hyprpm build packages: %s\n' "${missing_packages[*]}"
    printf '%s\n' \
        'Installing them through Omarchy...' \
        'Enter your password if Omarchy requests it.'
    omarchy pkg add "${missing_packages[@]}"
}

install_engine() {
    hyprpm_log="$(mktemp)"

    if hyprpm add "${engine_url}" 2>&1 | tee "${hyprpm_log}"; then
        return 0
    fi

    if ! grep -Eqi 'headers?[[:space:]]+outdated' "${hyprpm_log}"; then
        printf '\n%s\n' 'HyprWindowShade installation failed; see the error above.' >&2
        return 1
    fi

    printf '\n%s\n' \
        'Hyprland headers are outdated. Running hyprpm update...' \
        'Enter your password if hyprpm requests it.'
    hyprpm update

    if engine_registered; then
        printf '\n%s\n' 'HyprWindowShade was registered during the update.'
        return 0
    fi

    printf '\n%s\n' 'Retrying HyprWindowShade installation...'
    hyprpm add "${engine_url}"
}

printf '%s\n' \
    'OmaDecor effects installer' \
    '' \
    'This installs two external projects:' \
    '  1. HyprWindowShade through hyprpm (native Hyprland plugin).' \
    '  2. Hyprland-Shader in your user data directory (55 open/close pairs).' \
    '' \
    'Supported Hyprland release: 0.56.x.' \
    'Build requirements: cmake, cpio, pkg-config, git, g++, gcc, make.' \
    'Missing build dependencies will be installed through Omarchy.' \
    'Omarchy or hyprpm may request your password.' \
    'No file under /usr/share/omarchy will be modified.' \
    ''

read -r -p 'Continue? [y/N] ' answer
case "${answer}" in
    y|Y|yes|YES) ;;
    *) printf '%s\n' 'Cancelled.'; exit 0 ;;
esac

ensure_supported_hyprland
ensure_build_dependencies

if engine_registered; then
    printf '\n%s\n' 'HyprWindowShade is already registered with hyprpm.'
else
    printf '\n%s\n' 'Installing HyprWindowShade...'
    install_engine
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
