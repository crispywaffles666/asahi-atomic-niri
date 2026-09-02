#!/usr/bin/bash
# Check the image's packages, tools, settings, and boot chain.
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
    keyd
    distrobox
    flatpak
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
    # asahi-brightnessd reads sysfs; this package supplies sensor checks.
    iio-sensor-proxy
    file-roller
    file-roller-nautilus
    evince
    eog
    ffmpeg
    ffmpeg-libs
    x264-libs
    x265-libs
    ffmpegthumbnailer
    gstreamer1-plugin-libav
    gstreamer1-plugins-base
    gstreamer1-plugins-base-tools
    gstreamer1-plugins-good
    gstreamer1-plugins-bad-free
    gstreamer1-plugins-ugly-free
)

# Noctalia and niri replace these desktops.
FORBIDDEN_PACKAGES=(
    gnome-shell
    mutter
    gdm
    gnome-session
    plasma-desktop
    kwin
    sddm
)

# These PC and gaming packages do not belong in the Arm image.
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

# RPM Fusion supplies the software codecs, but its PC GPU driver replacements
# must never displace Fedora Asahi Remix's Mesa packages.
FORBIDDEN_FREEWORLD_MESA_PACKAGES=(
    mesa-va-drivers-freeworld
    mesa-vdpau-drivers-freeworld
    mesa-vulkan-drivers-freeworld
)

# Keep the Asahi hardware stack from the base image.
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

for package in "${FORBIDDEN_FREEWORLD_MESA_PACKAGES[@]}"; do
    if rpm -q --quiet "$package"; then
        fail "RPM Fusion Mesa must not replace the Asahi Mesa stack: $package"
    fi
done

for package in "${REQUIRED_ASAHI_PACKAGES[@]}"; do
    if ! rpm -q --quiet "$package"; then
        fail "required Asahi hardware package is missing: $package"
    fi
done

# Theme build dependencies and sources stay in the disposable builder stage.
if rpm -q --quiet sassc; then
    fail "theme build-only package leaked into the final image: sassc"
fi

GRAPHITE_THEME=/usr/share/themes/Graphite-purple-Dark-dracula
GRAPHITE_FILES=(
    "$GRAPHITE_THEME/index.theme"
    "$GRAPHITE_THEME/gtk-3.0/gtk.css"
    "$GRAPHITE_THEME/gtk-3.0/gtk-dark.css"
    "$GRAPHITE_THEME/gtk-4.0/gtk.css"
    "$GRAPHITE_THEME/gtk-4.0/gtk-dark.css"
)
for theme_file in "${GRAPHITE_FILES[@]}"; do
    [[ -s "$theme_file" ]] || fail "generated Graphite theme file is missing: $theme_file"
done
for asset_dir in "$GRAPHITE_THEME/gtk-3.0/assets" "$GRAPHITE_THEME/gtk-4.0/assets"; do
    if [[ ! -d "$asset_dir" || -z "$(find "$asset_dir" -type f -print -quit)" ]]; then
        fail "generated Graphite assets are missing: $asset_dir"
    fi
done

DRACULA_ICONS=/usr/share/icons/dracula-icons-main
[[ -s "$DRACULA_ICONS/index.theme" ]] \
    || fail "Dracula icon theme index is missing: $DRACULA_ICONS/index.theme"
[[ -s "$DRACULA_ICONS/icon-theme.cache" ]] \
    || fail "Dracula generated icon cache is missing: $DRACULA_ICONS/icon-theme.cache"
[[ -s /usr/share/licenses/Graphite-gtk-theme/LICENSE ]] \
    || fail "Graphite upstream license is missing"
[[ -s /usr/share/licenses/dracula-icons/README.md ]] \
    || fail "Dracula Icons upstream licensing notice is missing"

for gtk_settings in /etc/skel/.config/gtk-{3,4}.0/settings.ini; do
    grep -Fxq 'gtk-theme-name=Graphite-purple-Dark-dracula' "$gtk_settings" \
        || fail "configured GTK theme name is incorrect: $gtk_settings"
    grep -Fxq 'gtk-icon-theme-name=dracula-icons-main' "$gtk_settings" \
        || fail "configured icon theme name is incorrect: $gtk_settings"
done
THEME_SCHEMA=/usr/share/glib-2.0/schemas/zz_asahi-atomic-niri.gschema.override
grep -Fxq "gtk-theme='Graphite-purple-Dark-dracula'" "$THEME_SCHEMA" \
    || fail "GNOME schema override has the wrong GTK theme name"
grep -Fxq "icon-theme='dracula-icons-main'" "$THEME_SCHEMA" \
    || fail "GNOME schema override has the wrong icon theme name"

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
    monitor-sensor
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
    jq
    fastfetch
    pactl
    tailscaled
    uupd
    keyd
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
    ffmpegthumbnailer
    gzip
    update-m1n1
)

for binary in "${REQUIRED_BINARIES[@]}"; do
    command -v "$binary" >/dev/null 2>&1 || fail "required command not found: $binary"
done

# Full FFmpeg is intentional: require both common software decoders and the
# high-quality GPL encoders so a repository/package change cannot silently
# reduce the image back to Fedora's codec-limited build.
for decoder in h264 hevc; do
    ffmpeg -hide_banner -decoders 2>/dev/null | \
        awk -v codec="$decoder" '$2 == codec { found = 1 } END { exit !found }' || \
        fail "FFmpeg decoder is missing: $decoder"
done
for encoder in libx264 libx265; do
    ffmpeg -hide_banner -encoders 2>/dev/null | \
        awk -v codec="$encoder" '$2 == codec { found = 1 } END { exit !found }' || \
        fail "FFmpeg encoder is missing: $encoder"
done

# These Nautilus helpers live outside PATH.
GVFS_DAEMONS=(
    /usr/libexec/gvfsd-mtp
    /usr/libexec/gvfsd-archive
    /usr/libexec/gvfs-udisks2-volume-monitor
)
for d in "${GVFS_DAEMONS[@]}"; do
    [[ -x "$d" ]] || fail "required gvfs daemon not found: $d"
done

if [[ ! -x /usr/share/homebrew/home/linuxbrew/.linuxbrew/bin/brew ]]; then
    fail "staged homebrew binary not found in image"
fi

# Allow only known Arm images; Universal Blue toolbox images target PCs.
DISTROBOX_INI=/etc/distrobox/distrobox.ini
if [[ ! -r $DISTROBOX_INI ]]; then
    fail "distrobox manifest not found: $DISTROBOX_INI"
fi
if grep -Eq '^\s*image\s*=\s*(ghcr\.io/ublue-os|docker\.io/ublue|.*toolbox)' "$DISTROBOX_INI"; then
    fail "distrobox manifest must not reference Universal Blue x86 toolbox images"
fi
for img in 'docker.io/library/fedora' 'docker.io/library/ubuntu' \
           'docker.io/library/debian' 'docker.io/library/archlinux'; do
    grep -q "image=${img}" "$DISTROBOX_INI" || fail "distrobox manifest missing arm64 preset: $img"
done

if [[ ! -x /usr/libexec/asahi-niri/config-flatpaks.sh ]]; then
    fail "per-user flatpak bootstrap script not found / not executable"
fi
if [[ ! -f /usr/lib/systemd/user/config-flatpaks.service ]]; then
    fail "per-user flatpak bootstrap unit not found"
fi

# bootc lint needs a tmpfiles rule for each package-made path in /var.
if [[ ! -r /usr/lib/tmpfiles.d/zz-asahi-atomic-niri.conf ]]; then
    fail "missing bootc var-tmpfiles coverage: zz-asahi-atomic-niri.conf"
fi

# Parse all included files with the niri version in this image.
NIRI_SKEL=/etc/skel/.config/niri
if [[ ! -f "$NIRI_SKEL/config.kdl" ]]; then
    fail "skel niri config.kdl missing: $NIRI_SKEL/config.kdl"
fi
test_home="$(mktemp -d)"
mkdir -p "$test_home/.config"
cp -r "$NIRI_SKEL" "$test_home/.config/niri"
if ! HOME="$test_home" XDG_CONFIG_HOME="$test_home/.config" niri validate; then
    fail "skel niri config failed niri validate (removed option or broken include?)"
fi
rm -rf "$test_home"

# Each helper named by the starter config must ship with it.
skel_bin=/etc/skel/.local/bin
for helper_path in $(grep -rhoE '\$HOME/\.local/bin/[A-Za-z0-9._-]+\.sh' "$NIRI_SKEL" | sort -u || true); do
    helper="${helper_path##*/}"
    if [[ ! -x "$skel_bin/$helper" ]]; then
        fail "skel niri config spawns missing helper script: $helper"
    fi
done

if [[ ! -r /etc/skel/.config/keyd/default.conf ]]; then
    fail "skel keyd config missing: /etc/skel/.config/keyd/default.conf"
fi

# Ship the starter config without forcing nvim into the image.
if [[ ! -r /etc/skel/.config/nvim/init.lua ]]; then
    fail "skel nvim config missing: /etc/skel/.config/nvim/init.lua"
fi

# OSTree's zero file times require `gzip -n`; reject both drift and double edits.
UPDATE_M1N1=/usr/bin/update-m1n1
if [[ ! -f "$UPDATE_M1N1" ]]; then
    fail "patched update-m1n1 not found: $UPDATE_M1N1"
fi
safe_gzip=$(grep -Fxc 'gzip -nc "$U_BOOT" >>"${TARGET}.new"' "$UPDATE_M1N1" || true)
old_gzip=$(grep -Fxc 'gzip -c "$U_BOOT" >>"${TARGET}.new"' "$UPDATE_M1N1" || true)
if [[ "$safe_gzip" -ne 1 ]]; then
    fail "update-m1n1 must contain EXACTLY ONE 'gzip -nc ...' invocation (found $safe_gzip)"
fi
if [[ "$old_gzip" -ne 0 ]]; then
    fail "update-m1n1 still contains the unfixed 'gzip -c ...' invocation (found $old_gzip)"
fi

# /etc must load first, then the booted tree setting, then the first DTBS check.
override_count=$(grep -Fxc 'if [ -n "${ASAHI_ATOMIC_DTBS:-}" ]; then' "$UPDATE_M1N1" || true)
if [[ "$override_count" -ne 1 ]]; then
    fail "update-m1n1 must contain EXACTLY ONE ASAHI_ATOMIC_DTBS override (found $override_count)"
fi
if ! grep -Fxq '    DTBS="$ASAHI_ATOMIC_DTBS"' "$UPDATE_M1N1"; then
    fail "update-m1n1 ASAHI_ATOMIC_DTBS override missing its DTBS assignment line"
fi
config_line=$(grep -nF '[ -e /etc/sysconfig/update-m1n1 ] && . /etc/sysconfig/update-m1n1' "$UPDATE_M1N1" | head -n1 | cut -d: -f1 || true)
override_line=$(grep -nF 'if [ -n "${ASAHI_ATOMIC_DTBS:-}" ]; then' "$UPDATE_M1N1" | head -n1 | cut -d: -f1 || true)
check_line=$(grep -nF 'if [ -z "$DTBS" ]; then' "$UPDATE_M1N1" | head -n1 | cut -d: -f1 || true)
if [[ -z "$config_line" || -z "$override_line" || -z "$check_line" ]]; then
    fail "cannot locate config/override/DTBS-check lines in update-m1n1; ordering unprovable"
fi
if [[ "$config_line" -ge "$override_line" ]]; then
    fail "update-m1n1 ASAHI_ATOMIC_DTBS override is not applied after config sourcing"
fi
if [[ "$override_line" -ge "$check_line" ]]; then
    fail "update-m1n1 ASAHI_ATOMIC_DTBS override is not applied before the DTBS empty check"
fi

HELPER=/usr/libexec/asahi-atomic-niri/update-m1n1-helper.sh
if [[ ! -x "$HELPER" ]]; then
    fail "deployment-aware DTB/m1n1 helper not found or not executable: $HELPER"
fi

M1N1_UNIT=asahi-atomic-niri-update-m1n1.service
if [[ ! -f "/usr/lib/systemd/system/$M1N1_UNIT" ]]; then
    fail "m1n1 refresh systemd unit missing: $M1N1_UNIT"
fi
if [[ ! -L "/etc/systemd/system/multi-user.target.wants/$M1N1_UNIT" ]]; then
    fail "m1n1 refresh unit is not enabled (no multi-user.target.wants symlink)"
fi

KEYD_UNIT=keyd.service
if [[ ! -f "/usr/lib/systemd/system/$KEYD_UNIT" ]]; then
    fail "keyd systemd unit missing: $KEYD_UNIT"
fi
if [[ ! -L "/etc/systemd/system/multi-user.target.wants/$KEYD_UNIT" ]]; then
    fail "keyd unit is not enabled (no multi-user.target.wants symlink)"
fi

BRIGHTNESSD=/usr/sbin/asahi-brightnessd
if [[ ! -x "$BRIGHTNESSD" ]]; then
    fail "asahi-brightnessd binary missing or not executable: $BRIGHTNESSD"
fi
BRIGHTNESSD_UNIT=asahi-brightnessd.service
BRIGHTNESSD_UNIT_FILE="/usr/lib/systemd/system/$BRIGHTNESSD_UNIT"
if [[ ! -f "$BRIGHTNESSD_UNIT_FILE" ]]; then
    fail "asahi-brightnessd systemd unit missing: $BRIGHTNESSD_UNIT"
fi
if [[ ! -L "/etc/systemd/system/multi-user.target.wants/$BRIGHTNESSD_UNIT" ]]; then
    fail "asahi-brightnessd unit is not enabled (no multi-user.target.wants symlink)"
fi
start_cmd=$(grep -E '^ExecStart=' "$BRIGHTNESSD_UNIT_FILE" | head -n1)
if [[ -z "$start_cmd" ]]; then
    fail "asahi-brightnessd unit has no ExecStart"
fi
start_bin=${start_cmd#ExecStart=}
start_bin=${start_bin%% *}
if [[ ! -x "$start_bin" ]]; then
    fail "asahi-brightnessd unit ExecStart binary not found/executable: $start_bin"
fi
# Skip hosts without a keyboard light instead of looping on failure.
grep -Eq '^ConditionPathExists=/sys/class/leds/kbd_backlight/max_brightness' "$BRIGHTNESSD_UNIT_FILE" \
    || fail "asahi-brightnessd unit is missing the kbd-backlight ConditionPathExists"
# Upstream has no dry run. On build hosts with no light, it must fail without
# hanging. Never run it on a host where it could change the light.
if [[ ! -e /sys/class/leds/kbd_backlight ]]; then
    set +e
    timeout 10 "$BRIGHTNESSD" >/dev/null 2>&1
    brightnessd_status=$?
    set -e
    if [[ "$brightnessd_status" -eq 0 || "$brightnessd_status" -eq 124 ]]; then
        fail "asahi-brightnessd did not fail cleanly without hardware (exit $brightnessd_status)"
    fi
fi

# The helper must use the booted tree, not guess from sorted /boot paths.
if grep -Eq '/boot/ostree|sort -r|sort -V|tail -n 1|head -n 1|ls .*\|.*(head|tail|sort)' "$HELPER"; then
    fail "m1n1 helper appears to use unsafe glob-first/latest-directory logic"
fi
if ! grep -q 'uname -r' "$HELPER"; then
    fail "m1n1 helper does not key its DTB resolution off the booted deployment kernel (uname -r)"
fi
if ! grep -Eq '/dtb|/dtbs' "$HELPER"; then
    fail "m1n1 helper does not resolve a device-tree directory under the deployment module root"
fi
# dracut-asahi puts each tree's device files here.
if ! grep -q '/usr/lib/modules' "$HELPER"; then
    fail "m1n1 helper does not reference the standard /usr/lib/modules deployment tree"
fi
# Plain DTBS loses to /etc; the patched name loads after /etc.
if ! grep -q 'export ASAHI_ATOMIC_DTBS=' "$HELPER"; then
    fail "m1n1 helper does not export the ASAHI_ATOMIC_DTBS namespaced override"
fi
if grep -Eq '^[[:space:]]*export[[:space:]]+DTBS=' "$HELPER" \
   || grep -Eq '^[[:space:]]*export[[:space:]]+DTBS$' "$HELPER"; then
    fail "m1n1 helper still exports the plain DTBS variable (must use ASAHI_ATOMIC_DTBS)"
fi

SIG_KEY=/etc/pki/containers/ghcr.io-crispywaffles666-asahi-atomic-niri.pub
if [[ ! -s "$SIG_KEY" ]]; then
    fail "container signature public key missing: $SIG_KEY"
fi

SIGSTORE_CONFIG=/etc/containers/registries.d/ghcr.io-crispywaffles666-asahi-atomic-niri.yaml
if [[ ! -r "$SIGSTORE_CONFIG" ]]; then
    fail "registries sigstore config missing: $SIGSTORE_CONFIG"
fi
grep -q 'use-sigstore-attachments: true' "$SIGSTORE_CONFIG" \
    || fail "registries config missing use-sigstore-attachments"
grep -q 'ghcr.io/crispywaffles666/asahi-atomic-niri' "$SIGSTORE_CONFIG" \
    || fail "registries config missing GHCR namespace"

POLICY_FILE=/etc/containers/policy.json
if [[ ! -r "$POLICY_FILE" ]]; then
    fail "container policy missing: $POLICY_FILE"
fi
if command -v python3 >/dev/null 2>&1; then
    if ! python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$POLICY_FILE" 2>/dev/null; then
        fail "container policy is not valid JSON: $POLICY_FILE"
    fi
fi
grep -q '"ghcr.io/crispywaffles666/asahi-atomic-niri"' "$POLICY_FILE" \
    || fail "container policy missing GHCR namespace"
grep -q '"type": "sigstoreSigned"' "$POLICY_FILE" \
    || fail "container policy missing sigstoreSigned rule"

# Only uupd may fetch OS updates, and it must not reboot.
if [[ ! -r /etc/uupd/config.json ]]; then
    fail "uupd config missing: /etc/uupd/config.json"
fi
for timer in bootc-fetch-apply-updates.timer rpm-ostreed-automatic.timer; do
    if [[ ! -L "/etc/systemd/system/$timer" ]] || [[ "$(readlink "/etc/systemd/system/$timer")" != "/dev/null" ]]; then
        fail "auto-reboot-capable update timer is not masked: $timer"
    fi
done

# bootc makes /boot read-only, so this Fedora timer can only fail.
grub_mask=/etc/systemd/user/grub-boot-success.timer
if [[ ! -L "$grub_mask" ]] || [[ "$(readlink "$grub_mask")" != "/dev/null" ]]; then
    fail "grub-boot-success.timer user unit is not globally masked"
fi

# Test the installed U-Boot without writing to the ESP.
if ! "$HELPER" gzip-check; then
    fail "gzip -nc self-test against installed U-Boot failed"
fi

# Run the patched script with a false /etc setting and a true booted-tree setting.
# Temp paths keep the test from touching the ESP.
test_root="$(mktemp -d)"
clean_test() { rm -rf "${test_root:-}"; }
trap clean_test EXIT
mkdir -p "$test_root/apple"

test_script="$test_root/update-m1n1"
cp "$UPDATE_M1N1" "$test_script"
chmod +x "$test_script"

# Change only the two write paths; keep the setting order under test intact.
sed -i \
    -e "s|^\[ -e /etc/sysconfig/update-m1n1 \] \&\& \. /etc/sysconfig/update-m1n1\$|[ -e \"\$test_default\" ] \&\& . \"\$test_default\"|" \
    -e 's|^m1n1config=/run/m1n1\.conf$|m1n1config="$ASAHI_ATOMIC_TMP"/m1n1.conf|' \
    "$test_script"

# The copied script loads functions.sh from its own folder.
cat > "$test_root/functions.sh" <<'EOF'
#!/bin/sh
warn()  { echo "WARN: $*" >&2; }
info()  { echo "INFO: $*" >&2; }
mount_sys_esp() { mkdir -p "$1"; }
EOF

# The false value must lose to ASAHI_ATOMIC_DTBS below.
printf 'DTBS=/definitely/wrong/stale-dtb\n' > "$test_root/fake-default"
printf 'CORRECT-DEPLOYMENT-DTB\n'   > "$test_root/apple/t6MARKER.dtb"
printf 'CORRECT-DEPLOYMENT-DTB2\n'  > "$test_root/apple/t81MARKER.dtb"

printf 'M1N1PAYLOAD\n'  > "$test_root/m1n1.bin"
printf 'UBOOTNODTB\n'   > "$test_root/u-boot-nodtb.bin"

test_out="$test_root/boot.bin"
if ! ( cd "$test_root" && \
       ASAHI_ATOMIC_TMP="$test_root" \
       test_default="$test_root/fake-default" \
       M1N1="$test_root/m1n1.bin" \
       U_BOOT="$test_root/u-boot-nodtb.bin" \
       TARGET="$test_out" \
       ASAHI_ATOMIC_DTBS="$test_root" \
       sh "$test_script" >/dev/null 2>&1 ); then
    fail "patched update-m1n1 conflicting-config behavioral run failed"
fi
if ! grep -q 'CORRECT-DEPLOYMENT-DTB' "$test_out"; then
    fail "ASAHI_ATOMIC_DTBS override lost: payload does not contain deployment DTB"
fi
if grep -Eq 'definitely/wrong|/stale-dtb' "$test_out"; then
    fail "stale config DTBS won: payload contains wrong/stale DTB path"
fi
trap - EXIT
clean_test

echo "Image validation passed."
