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
    ndiswrapper
    akmod-nvidia
    xorg-x11-drv-nvidia
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
)

for binary in "${REQUIRED_BINARIES[@]}"; do
    command -v "$binary" >/dev/null 2>&1 || fail "required command not found: $binary"
done

# Homebrew is staged as image-owned content under /usr/share/homebrew and copied
# into /var/home/linuxbrew at first boot by brew-setup.service.
if [[ ! -x /usr/share/homebrew/home/linuxbrew/.linuxbrew/bin/brew ]]; then
    fail "staged homebrew binary not found in image"
fi

echo "Image validation passed."
