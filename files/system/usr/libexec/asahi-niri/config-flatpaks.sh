#!/usr/bin/bash
# Install the image's default per-user Flatpaks into the current user's
# flatpak install on first login. Idempotent: a marker file in
# ~/.local/state ensures this runs only once per user, so later logins are a
# no-op even when nothing needs installing (avoids repeated boot-time work and
# notifications on every login, matching the "notify: false" default-flatpaks
# behavior used elsewhere).
#
# Requires: flatpak, a reachable Flathub remote. The system-wide Flathub remote
# (flathub-setup.service) is used for installs so each user does not need to
# keep their own copy; a user remote is only added if one is missing.
#
# Apps here are the ones this image relies on for desktop integration, all of
# which publish a linux/arm64 manifest on Flathub:
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

# Ensure a Flathub remote exists for this user (system remote if present, else
# a per-user one), then install the configured apps non-interactively.
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
