#!/usr/bin/bash
# A mark keeps later logins from installing these apps again. User installs
# need a user Flathub remote even when a system remote already exists.
set -euo pipefail

marker="${HOME}/.local/state/config-flatpaks.done"
[[ -f "$marker" ]] && exit 0

apps=(
    com.github.tchx84.Flatseal
    io.github.flattool.Warehouse
    it.mijorus.smile
)

flatpak remote-add --user --if-not-exists flathub \
    https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install --user --noninteractive --assumeyes flathub "${apps[@]}"

mkdir -p "$(dirname "$marker")"
touch "$marker"
