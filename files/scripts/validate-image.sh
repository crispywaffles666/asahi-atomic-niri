#!/usr/bin/bash
# Validate the final image composition. Fails the build if required desktop
# packages are missing or if forbidden GNOME desktop packages are present.
# Also verifies that no Asahi hardware packages are missing and that no
# x86_64-only / gaming packages are present.
set -euxo pipefail

REQUIRED_PACKAGES=(
    niri
    noctalia
    greetd
    tuigreet
    gnome-keyring
    xdg-desktop-portal-gnome
    xdg-desktop-portal-gtk
    nautilus
    tailscale
    uupd
    # Containerized dev environments + Flatpak runtime
    distrobox
    flatpak
    # "Boring desktop plumbing" the minimal base-atomic image does not ship
    udisks2
    gvfs
    gvfs-mtp
    gvfs-archive
    gvfs-fuse
    gnome-disk-utility
    cups
    bluez
    blueman
    power-profiles-daemon
    file-roller
    file-roller-nautilus
    evince
    eog
    # Host-native multimedia codecs (software decode)
    ffmpeg-free
    gstreamer1-plugins-base
    gstreamer1-plugins-base-tools
    gstreamer1-plugins-good
    gstreamer1-plugins-bad-free
    gstreamer1-plugins-ugly-free
)

# GNOME/KDE desktop packages that must NOT be present (Noctalia + niri replace them)
FORBIDDEN_PACKAGES=(
    gnome-shell
    mutter
    gdm
    gnome-session
    plasma-desktop
    kwin
    sddm
)

# Bazzite/gaming/x86-specific packages that must NOT leak into this image
FORBIDDEN_GAMING_PACKAGES=(
    steam
    lutris
    proton
    wine
    gamescope
    manugamp
    vkBasalt
    xone
    openrazer
    ndiswrapper
    akmod-nvidia
    xorg-x11-drv-nvidia
    displaylink
    mangohud
)

# Core packages that the Asahi bootable container must retain (brought in by
# the base-atomic image). Their presence checks guard against accidental
# removal of the Asahi hardware stack.
REQUIRED_ASAHI_PACKAGES=(
    asahi-platform-metapackage
    asahi-repos
    dracut-asahi
    update-m1n1
    alsa-ucm-asahi
)

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

for package in "${REQUIRED_PACKAGES[@]}"; do
    if ! rpm -q --quiet "$package"; then
        fail "required package is not installed: $package"
    fi
done

for package in "${FORBIDDEN_PACKAGES[@]}"; do
    if rpm -q --quiet "$package"; then
        fail "forbidden desktop package is installed: $package"
    fi
done

for package in "${FORBIDDEN_GAMING_PACKAGES[@]}"; do
    if rpm -q --quiet "$package"; then
        fail "forbidden gaming/x86 package is installed: $package"
    fi
done

for package in "${REQUIRED_ASAHI_PACKAGES[@]}"; do
    if ! rpm -q --quiet "$package"; then
        fail "required Asahi hardware package is missing: $package"
    fi
done

# Verify every configured command referenced by Niri/Noctalia/helper scripts exists
REQUIRED_BINARIES=(
    niri
    niri-session
    noctalia
    alacritty
    ghostty
    satty
    brave-origin
    nautilus
    xwayland-satellite
    playerctl
    brightnessctl
    wl-copy
    wl-paste
    wtype
    pavucontrol
    cava
    seahorse
    zsh
    bat
    micro
    geany
    rg
    yazi
    starship
    inotifywait
    notify-send
    xdg-open
    fastfetch
    pactl
    tailscaled
    uupd
    distrobox
    flatpak
    gsettings
    udisksctl
    gnome-disks
    lpstat
    blueman-applet
    evince
    eog
    file-roller
    powerprofilesctl
    gst-inspect-1.0
    ffmpeg
    ffprobe
)

for binary in "${REQUIRED_BINARIES[@]}"; do
    command -v "$binary" >/dev/null 2>&1 || fail "required command not found: $binary"
done

# gvfs backends for Nautilus live in /usr/libexec (not on PATH), so check their
# absolute paths directly: MTP (phones/tablets), archives (zip mount via
# gvfs-archive), and removable-media volume monitoring (via udisks2/gvfs).
GVFS_DAEMONS=(
    /usr/libexec/gvfsd-mtp
    /usr/libexec/gvfsd-archive
    /usr/libexec/gvfs-udisks2-volume-monitor
)
for d in "${GVFS_DAEMONS[@]}"; do
    [[ -x "$d" ]] || fail "required gvfs daemon not found: $d"
done

# Homebrew is staged as image-owned content under /usr/share/homebrew and copied
# into /var/home/linuxbrew at first boot by brew-setup.service.
if [[ ! -x /usr/share/homebrew/home/linuxbrew/.linuxbrew/bin/brew ]]; then
    fail "staged homebrew binary not found in image"
fi

# Distrobox assembly manifest: must exist, declare only known-multi-arch
# (linux/arm64) base images, and must NOT reference any x86-only Universal Blue
# toolbox / distrobox image (those are for PC/Bazzite, not Apple Silicon).
DISTROBOX_INI=/etc/distrobox/distrobox.ini
if [[ ! -r $DISTROBOX_INI ]]; then
    fail "distrobox manifest not found: $DISTROBOX_INI"
fi
if grep -Eq '^\s*image\s*=\s*(ghcr\.io/ublue-os|docker\.io/ublue|.*toolbox)' "$DISTROBOX_INI"; then
    fail "distrobox manifest must not reference Universal Blue x86 toolbox images"
fi
# Sanity: every preset references one of the known arm64 base images.
for img in 'docker.io/library/fedora' 'docker.io/library/ubuntu' \
           'docker.io/library/debian' 'docker.io/library/archlinux'; do
    grep -q "image=${img}" "$DISTROBOX_INI" || fail "distrobox manifest missing arm64 preset: $img"
done

# Per-user Flatpak bootstrap: the helper script and user unit must be present so
# Flatseal / Warehouse / Smile install on first login.
if [[ ! -x /usr/libexec/asahi-niri/config-flatpaks.sh ]]; then
    fail "per-user flatpak bootstrap script not found / not executable"
fi
if [[ ! -f /usr/lib/systemd/user/config-flatpaks.service ]]; then
    fail "per-user flatpak bootstrap unit not found"
fi

# bootc lint (var-tmpfiles) requires the /var/lib dirs that blueman and
# power-profiles-daemon bake in to be declared by a tmpfiles.d entry; keep that
# coverage present so `bootc container lint --fatal-warnings` keeps passing.
if [[ ! -r /usr/lib/tmpfiles.d/zz-asahi-atomic-niri.conf ]]; then
    fail "missing bootc var-tmpfiles coverage: zz-asahi-atomic-niri.conf"
fi

echo "Image validation passed."
