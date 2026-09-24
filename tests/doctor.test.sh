#!/usr/bin/env bash

set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_home=$(mktemp -d)
trap 'rm -rf -- "$test_home"' EXIT
export HOME="$test_home"
mkdir -p "$HOME/.config/omarchy/plugins/omadecor"
cp "$repo_dir/manifest.json" "$HOME/.config/omarchy/plugins/omadecor/manifest.json"

omarchy() {
    printf '%s\n' '[{"id":"omadecor","enabled":true}]'
}
hyprctl() {
    if [[ $1 == version ]]; then
        printf '%s\n' '{"version":"0.56.2"}'
    elif [[ ${MOCK_NATIVE:-yes} == yes ]]; then
        printf '%s\n' '[{"name":"omadecor-native"}]'
    else
        printf '%s\n' '[]'
    fi
}
hyprpm() {
    if [[ ${MOCK_REGISTERED:-yes} == yes ]]; then
        printf '%s\n' 'Repository OmaDecor:' '  Plugin omadecor-native'
        printf '  enabled: \033[32mtrue\033[0m\n'
    elif [[ ${MOCK_REGISTERED:-yes} == disabled ]]; then
        printf '%s\n' 'Repository OmaDecor:' '  Plugin omadecor-native' '  enabled: false'
    else
        printf '%s\n' 'Repository HyprWindowShade:' '  Plugin HyprWindowShade'
    fi
}
export -f omarchy hyprctl hyprpm

printf '%s\n' '{"bar":{"layout":{"left":[],"center":[],"right":[{"id":"omadecor"}]}}}' \
    >"$HOME/.config/omarchy/shell.json"
healthy_output=$(bash "$repo_dir/scripts/doctor.sh")
grep -Fq 'Installation checks passed.' <<<"$healthy_output"

export MOCK_REGISTERED=no
if unregistered_output=$(bash "$repo_dir/scripts/doctor.sh"); then
    printf '%s\n' 'Expected an unregistered native plugin to fail.' >&2
    exit 1
fi
grep -Fq 'a manual load is session-only' <<<"$unregistered_output"

export MOCK_REGISTERED=disabled
if disabled_output=$(bash "$repo_dir/scripts/doctor.sh"); then
    printf '%s\n' 'Expected a disabled hyprpm plugin to fail.' >&2
    exit 1
fi
grep -Fq 'not enabled in hyprpm' <<<"$disabled_output"

export MOCK_NATIVE=no
printf '%s\n' '{"bar":{"layout":{"left":[],"center":[],"right":[]}}}' \
    >"$HOME/.config/omarchy/shell.json"
if incomplete_output=$(bash "$repo_dir/scripts/doctor.sh"); then
    printf '%s\n' 'Expected a missing widget and native plugin to fail.' >&2
    exit 1
fi
grep -Fq 'OD widget is not found' <<<"$incomplete_output"
grep -Fq 'Native decoration is not loaded' <<<"$incomplete_output"

printf '%s\n' 'doctor tests passed'
