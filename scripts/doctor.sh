#!/usr/bin/env bash

# Read-only installation check. Never enables, reloads, or installs a plugin.
set -euo pipefail

problems=0

ok() { printf 'OK   %s\n' "$1"; }
info() { printf 'INFO %s\n' "$1"; }
issue() {
    printf 'FIX  %s\n' "$1"
    problems=$((problems + 1))
}

if [[ ${1:-} == --help && $# == 1 ]]; then
    printf '%s\n' 'Usage: bash scripts/doctor.sh' 'Read-only check of the OmaDecor installation in the current session.'
    exit 0
fi
if (( $# != 0 )); then
    printf 'Unknown argument: %s\n' "$1" >&2
    exit 2
fi

printf '%s\n' 'OmaDecor installation check (read-only)'

for tool in jq omarchy hyprctl hyprpm; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        issue "Missing $tool in PATH. Install Omarchy/Hyprland prerequisites first."
    fi
done

if ! command -v jq >/dev/null 2>&1; then
    exit 1
fi

installed_dir="${HOME}/.config/omarchy/plugins/omadecor"
if [[ -f $installed_dir/manifest.json ]] &&
    jq -e '.id == "omadecor"' "$installed_dir/manifest.json" >/dev/null 2>&1; then
    installed_version=$(jq -r '.version // "unknown"' "$installed_dir/manifest.json")
    ok "Omarchy plugin files installed (version $installed_version)."
    if [[ ! -d $installed_dir/.git ]]; then
        info 'This plugin directory is not a git checkout; omarchy plugin update cannot refresh it.'
    fi
else
    issue 'Omarchy plugin files missing. Run: omarchy plugin add https://github.com/ZA512/OmaDecor.git --enable'
fi

if command -v omarchy >/dev/null 2>&1; then
    if plugins_json=$(omarchy plugin list --json 2>/dev/null) &&
        jq -e 'type == "array"' <<<"$plugins_json" >/dev/null 2>&1; then
        if jq -e 'any(.[]; .id == "omadecor" and .enabled == true)' <<<"$plugins_json" >/dev/null; then
            ok 'OmaDecor is enabled in Omarchy.'
        else
            issue 'OmaDecor is not enabled. Run: omarchy plugin enable omadecor'
        fi
    else
        issue 'Omarchy plugin list unavailable; check that omarchy-shell is running.'
    fi
fi

shell_config="${HOME}/.config/omarchy/shell.json"
if [[ -f $shell_config ]] &&
    jq -e '[.bar.layout.left[]?, .bar.layout.center[]?, .bar.layout.right[]?] | any(.[]; .id == "omadecor")' \
        "$shell_config" >/dev/null 2>&1; then
    ok 'OD widget is placed on the bar.'
else
    issue 'OD widget is not found in the user bar layout. Run: omarchy bar put omadecor --section right'
fi

if command -v hyprctl >/dev/null 2>&1; then
    if version_json=$(hyprctl version -j 2>/dev/null) &&
        jq -e 'type == "object" and (.version | type == "string")' <<<"$version_json" >/dev/null 2>&1; then
        version=$(jq -r '.version' <<<"$version_json")
        if [[ $version == 0.56 || $version == 0.56.* ]]; then
            ok "Running Hyprland $version is in the supported 0.56.x series."
        else
            issue "Hyprland $version is outside the validated 0.56.x series; use a matching OmaDecor release."
        fi
    else
        issue 'Cannot query the running Hyprland version.'
    fi

    if native_json=$(hyprctl plugin list -j 2>/dev/null) &&
        jq -e 'type == "array"' <<<"$native_json" >/dev/null 2>&1; then
        if jq -e 'any(.[]; .name == "omadecor-native")' <<<"$native_json" >/dev/null; then
            ok 'Native OmaDecor decoration is loaded in Hyprland.'
        else
            issue 'Native decoration is not loaded. Run: hyprpm enable omadecor-native; hyprpm reload'
        fi
        if jq -e 'any(.[]; .name == "HyprWindowShade")' <<<"$native_json" >/dev/null; then
            info 'Optional HyprWindowShade effects engine is loaded.'
        else
            info 'Optional HyprWindowShade effects engine is not loaded.'
        fi
    else
        issue 'Cannot query loaded Hyprland plugins.'
    fi
fi

if command -v hyprpm >/dev/null 2>&1; then
    if hyprpm_list=$(hyprpm list 2>/dev/null); then
        escape=$'\033'
        hyprpm_list=$(sed -E "s/${escape}\\[[0-9;]*[[:alpha:]]//g" <<<"$hyprpm_list")
        if grep -F -A1 'Plugin omadecor-native' <<<"$hyprpm_list" |
            grep -Eq 'enabled:[[:space:]]*true'; then
            ok 'Native decoration is registered and enabled in hyprpm.'
        else
            issue 'Native decoration is not enabled in hyprpm (a manual load is session-only). If absent, run: hyprpm add https://github.com/ZA512/OmaDecor.git; then: hyprpm enable omadecor-native; hyprpm reload'
        fi
    else
        issue 'Cannot inspect hyprpm registration.'
    fi
fi

if (( problems == 0 )); then
    printf '%s\n' 'Installation checks passed.'
else
    printf '%s\n' "$problems installation check(s) need attention."
fi
(( problems == 0 ))
