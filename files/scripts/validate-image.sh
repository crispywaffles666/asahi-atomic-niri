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
    gzip
    update-m1n1
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

# ---------------------------------------------------------------------------
# Asahi Atomic boot-chain hardening validation
# ---------------------------------------------------------------------------

# 1) The stock `update-m1n1` must carry the Atomic-safe gzip invocation and
#    MUST NOT retain the unfixed one. Exactly one safe invocation expected.
UPDATE_M1N1=/usr/bin/update-m1n1
if [[ ! -f "$UPDATE_M1N1" ]]; then
    fail "patched update-m1n1 not found: $UPDATE_M1N1"
fi
_safe_gzip=$(grep -Fxc 'gzip -nc "$U_BOOT" >>"${TARGET}.new"' "$UPDATE_M1N1" || true)
_bad_gzip=$(grep -Fxc 'gzip -c "$U_BOOT" >>"${TARGET}.new"' "$UPDATE_M1N1" || true)
if [[ "$_safe_gzip" -ne 1 ]]; then
    fail "update-m1n1 must contain EXACTLY ONE 'gzip -nc ...' invocation (found $_safe_gzip)"
fi
if [[ "$_bad_gzip" -ne 0 ]]; then
    fail "update-m1n1 still contains the unfixed 'gzip -c ...' invocation (found $_bad_gzip)"
fi

# 2) Deployment-aware DTB helper must exist and be executable.
HELPER=/usr/libexec/asahi-atomic-niri/update-m1n1-helper.sh
if [[ ! -x "$HELPER" ]]; then
    fail "deployment-aware DTB/m1n1 helper not found or not executable: $HELPER"
fi

# 3) m1n1 refresh systemd unit exists and is enabled for multi-user.
UNIT=asahi-atomic-niri-update-m1n1.service
if [[ ! -f "/usr/lib/systemd/system/$UNIT" ]]; then
    fail "m1n1 refresh systemd unit missing: $UNIT"
fi
if [[ ! -L "/etc/systemd/system/multi-user.target.wants/$UNIT" ]]; then
    fail "m1n1 refresh unit is not enabled (no multi-user.target.wants symlink)"
fi

# 4) The helper must NOT use unsafe glob-first / latest-directory selection.
#    It must resolve DTBs from the booted deployment's own /usr tree (keyed off
#    the booted kernel release), never by scanning /boot/ostree/* or picking the
#    lexicographically-newest directory.
if grep -Eq '/boot/ostree|sort -r|sort -V|tail -n 1|head -n 1|ls .*\|.*(head|tail|sort)' "$HELPER"; then
    fail "m1n1 helper appears to use unsafe glob-first/latest-directory logic"
fi
if ! grep -q 'uname -r' "$HELPER"; then
    fail "m1n1 helper does not key its DTB resolution off the booted deployment kernel (uname -r)"
fi
if ! grep -Eq '/dtb|/dtbs' "$HELPER"; then
    fail "m1n1 helper does not resolve a device-tree directory under the deployment module root"
fi
# The module root must resolve to the standard /usr/lib/modules location by
# default (that is where dracut-asahi installs each deployment's DTBs).
if ! grep -q '/usr/lib/modules' "$HELPER"; then
    fail "m1n1 helper does not reference the standard /usr/lib/modules deployment tree"
fi

# 5) Container signature public key must be present.
SIG_KEY=/etc/pki/containers/ghcr.io-crispywaffles666-asahi-atomic-niri.pub
if [[ ! -s "$SIG_KEY" ]]; then
    fail "container signature public key missing: $SIG_KEY"
fi

# 6) Registries sigstore config must exist and enable sigstore attachments for
#    this exact GHCR namespace.
REGCFG=/etc/containers/registries.d/ghcr.io-crispywaffles666-asahi-atomic-niri.yaml
if [[ ! -r "$REGCFG" ]]; then
    fail "registries sigstore config missing: $REGCFG"
fi
grep -q 'use-sigstore-attachments: true' "$REGCFG" \
    || fail "registries config missing use-sigstore-attachments"
grep -q 'ghcr.io/crispywaffles666/asahi-atomic-niri' "$REGCFG" \
    || fail "registries config missing GHCR namespace"

# 7) Container policy must contain the expected GHCR namespace and be JSON.
POLICY=/etc/containers/policy.json
if [[ ! -r "$POLICY" ]]; then
    fail "container policy missing: $POLICY"
fi
if command -v python3 >/dev/null 2>&1; then
    if ! python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$POLICY" 2>/dev/null; then
        fail "container policy is not valid JSON: $POLICY"
    fi
fi
grep -q '"ghcr.io/crispywaffles666/asahi-atomic-niri"' "$POLICY" \
    || fail "container policy missing GHCR namespace"
grep -q '"type": "sigstoreSigned"' "$POLICY" \
    || fail "container policy missing sigstoreSigned rule"

# 8) Update configuration must never auto-reboot: the only auto-update timer is
#    uupd (stage-only), and the bootc/rpm-ostree auto-apply timers are masked.
if [[ ! -r /etc/uupd/config.json ]]; then
    fail "uupd config missing: /etc/uupd/config.json"
fi
for _t in bootc-fetch-apply-updates.timer rpm-ostreed-automatic.timer; do
    if [[ ! -L "/etc/systemd/system/$_t" ]] || [[ "$(readlink "/etc/systemd/system/$_t")" != "/dev/null" ]]; then
        fail "auto-reboot-capable update timer is not masked: $_t"
    fi
done

# 9) Non-destructive, build-time-safe proof that the patched `gzip -nc` works
#    against the installed U-Boot without writing the ESP.
if ! "$HELPER" gzip-check; then
    fail "gzip -nc self-test against installed U-Boot failed"
fi

echo "Image validation passed."
