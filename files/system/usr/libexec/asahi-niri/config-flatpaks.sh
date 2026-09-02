#!/usr/bin/bash
# A mark keeps later logins from installing these apps again. Use the system
# Flathub when it exists; add a user copy only when needed.
set -euo pipefail

marker="${HOME}/.local/state/config-flatpaks.done"
[[ -f "$marker" ]] && exit 0

apps=(
    com.github.tchx84.Flatseal
    io.github.flattool.Warehouse
    it.mijorus.smile
)

if flatpak remotes --user --columns=name 2>/dev/null | grep -qx 'flathub'; then
    remote_repo="flathub"
elif flatpak remotes --system --columns=name 2>/dev/null | grep -qx 'flathub'; then
    flatpak remote-add --user --if-not-exists flathub \
        https://dl.flathub.org/repo/flathub.flatpakrepo
    remote_repo="flathub"
else
    flatpak remote-add --user --if-not-exists flathub \
        https://dl.flathub.org/repo/flathub.flatpakrepo
    remote_repo="flathub"
fi

flatpak install --user --noninteractive --assumeyes "$remote_repo" "${apps[@]}"

mkdir -p "$(dirname "$marker")"
touch "$marker"
