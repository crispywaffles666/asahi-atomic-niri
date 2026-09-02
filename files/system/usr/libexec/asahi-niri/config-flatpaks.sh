#!/usr/bin/bash
# Install the image's default per-user Flatpaks on first login. Idempotent: a
# marker in ~/.local/state makes later logins a no-op, so boot doesn't reinstall
# or re-notify.
#
# Requires: flatpak, a reachable Flathub remote. Installs through the system
# Flathub remote (flathub-setup.service adds it) so each user needn't keep a
# copy; a user remote is only added if one is missing.
#
# These three apps are the ones this image relies on for desktop integration,
# and each publishes a linux/arm64 manifest on Flathub:
#   - com.github.tchx84.Flatseal  (Flatpak permission manager)
#   - io.github.flattool.Warehouse (Flatpak app/remnant manager)
#   - it.mijorus.smile              (emoji picker, used by smile-paste.sh)
set -euo pipefail

marker="${HOME}/.local/state/config-flatpaks.done"
[[ -f "$marker" ]] && exit 0

apps=(
    com.github.tchx84.Flatseal
    io.github.flattool.Warehouse
    it.mijorus.smile
)

# Add a Flathub user remote if none exists, then install the apps silently.
if flatpak remotes --user --columns=name 2>/dev/null | grep -qx 'flathub'; then
    remote_repo="flathub"
elif flatpak remotes --system --columns=name 2>/dev/null | grep -qx 'flathub'; then
    flatpak remote-add --user --if-not-exists flathub \
        https://dl.flathub.org/repo/flathub.flatpakrepo
    remote_repo="flathub"
else
    # No Flathub remote of any kind; add one for this user so the install works.
    flatpak remote-add --user --if-not-exists flathub \
        https://dl.flathub.org/repo/flathub.flatpakrepo
    remote_repo="flathub"
fi

flatpak install --user --noninteractive --assumeyes "$remote_repo" "${apps[@]}"

mkdir -p "$(dirname "$marker")"
touch "$marker"
