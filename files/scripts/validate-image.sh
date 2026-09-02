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
    keyd
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
    # Standard sensor userspace for the Apple Silicon ALS (diagnostics:
    # monitor-sensor / D-Bus). asahi-brightnessd reads IIO sysfs directly.
    iio-sensor-proxy
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
# Niri skel config must parse with the niri version installed in this image
# ---------------------------------------------------------------------------
# `niri validate` parses the whole config.hierarchy (config.kdl + includes) and
# fails closed on removed syntax. This is what the stale pre-25.08 cfg tripped
# on (kind= animations, matches=[], geometry{...}, renamed bind actions) while
# old CI only grepped filenames. Runtime niri in the image is new enough.
NIRI_SKEL=/etc/skel/.config/niri
if [[ ! -f "$NIRI_SKEL/config.kdl" ]]; then
    fail "skel niri config.kdl missing: $NIRI_SKEL/config.kdl"
fi
_validate_home="$(mktemp -d)"
mkdir -p "$_validate_home/.config"
cp -r "$NIRI_SKEL" "$_validate_home/.config/niri"
if ! HOME="$_validate_home" XDG_CONFIG_HOME="$_validate_home/.config" niri validate; then
    fail "skel niri config failed niri validate (removed option or broken include?)"
fi
rm -rf "$_validate_home"

# Every $HOME/.local/bin/ helper the skel niri config spawns must actually ship
# (executable) in the skel, so autostart/keybinds can't point at a script the
# image does not provide.
_skel_bin=/etc/skel/.local/bin
for _ref in $(grep -rhoE '\$HOME/\.local/bin/[A-Za-z0-9._-]+\.sh' "$NIRI_SKEL" | sort -u || true); do
    _script="${_ref##*/}"
    if [[ ! -x "$_skel_bin/$_script" ]]; then
        fail "skel niri config spawns missing helper script: $_script"
    fi
done

# keyd remap config ships in the skel so new users get the Mac key layer without
# any manual setup (keyd reads ~/.config/keyd/default.conf in addition to
# /etc/keyd/; matches the owner's live dotfiles).
if [[ ! -r /etc/skel/.config/keyd/default.conf ]]; then
    fail "skel keyd config missing: /etc/skel/.config/keyd/default.conf"
fi

# nvim config ships in the skel (bootstrap for users who install nvim
# themselves); it is NOT required to have nvim installed in the image.
if [[ ! -r /etc/skel/.config/nvim/init.lua ]]; then
    fail "skel nvim config missing: /etc/skel/.config/nvim/init.lua"
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

# 1b) Namespaced DTB override must be present EXACTLY ONCE and ordered so it is
#     applied after the stock config is sourced but before DTBS is validated.
_override_count=$(grep -Fxc 'if [ -n "${ASAHI_ATOMIC_DTBS:-}" ]; then' "$UPDATE_M1N1" || true)
if [[ "$_override_count" -ne 1 ]]; then
    fail "update-m1n1 must contain EXACTLY ONE ASAHI_ATOMIC_DTBS override (found $_override_count)"
fi
if ! grep -Fxq '    DTBS="$ASAHI_ATOMIC_DTBS"' "$UPDATE_M1N1"; then
    fail "update-m1n1 ASAHI_ATOMIC_DTBS override missing its DTBS assignment line"
fi
# The override must appear after the stock config source line ...
_config_line_n=$(grep -nF '[ -e /etc/sysconfig/update-m1n1 ] && . /etc/sysconfig/update-m1n1' "$UPDATE_M1N1" | head -n1 | cut -d: -f1 || true)
_override_line_n=$(grep -nF 'if [ -n "${ASAHI_ATOMIC_DTBS:-}" ]; then' "$UPDATE_M1N1" | head -n1 | cut -d: -f1 || true)
_check_line_n=$(grep -nF 'if [ -z "$DTBS" ]; then' "$UPDATE_M1N1" | head -n1 | cut -d: -f1 || true)
if [[ -z "$_config_line_n" || -z "$_override_line_n" || -z "$_check_line_n" ]]; then
    fail "cannot locate config/override/DTBS-check lines in update-m1n1; ordering unprovable"
fi
if [[ "$_config_line_n" -ge "$_override_line_n" ]]; then
    fail "update-m1n1 ASAHI_ATOMIC_DTBS override is not applied after config sourcing"
fi
if [[ "$_override_line_n" -ge "$_check_line_n" ]]; then
    fail "update-m1n1 ASAHI_ATOMIC_DTBS override is not applied before the DTBS empty check"
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

# 3b) keyd remapping daemon unit exists and is enabled for multi-user.
KEYD_UNIT=keyd.service
if [[ ! -f "/usr/lib/systemd/system/$KEYD_UNIT" ]]; then
    fail "keyd systemd unit missing: $KEYD_UNIT"
fi
if [[ ! -L "/etc/systemd/system/multi-user.target.wants/$KEYD_UNIT" ]]; then
    fail "keyd unit is not enabled (no multi-user.target.wants symlink)"
fi

# 3c) Ambient-light auto-brightness daemon (asahi-brightnessd).
BRIGHTNESSD=/usr/sbin/asahi-brightnessd
if [[ ! -x "$BRIGHTNESSD" ]]; then
    fail "asahi-brightnessd binary missing or not executable: $BRIGHTNESSD"
fi
BRIGHTNESSD_UNIT=asahi-brightnessd.service
UNIT_FILE="/usr/lib/systemd/system/$BRIGHTNESSD_UNIT"
if [[ ! -f "$UNIT_FILE" ]]; then
    fail "asahi-brightnessd systemd unit missing: $BRIGHTNESSD_UNIT"
fi
if [[ ! -L "/etc/systemd/system/multi-user.target.wants/$BRIGHTNESSD_UNIT" ]]; then
    fail "asahi-brightnessd unit is not enabled (no multi-user.target.wants symlink)"
fi
# The unit must reference a real, executable binary.
_execstart=$(grep -E '^ExecStart=' "$UNIT_FILE" | head -n1)
if [[ -z "$_execstart" ]]; then
    fail "asahi-brightnessd unit has no ExecStart"
fi
_execstart_bin=${_execstart#ExecStart=}
_execstart_bin=${_execstart_bin%% *}
if [[ ! -x "$_execstart_bin" ]]; then
    fail "asahi-brightnessd unit ExecStart binary not found/executable: $_execstart_bin"
fi
# The unit must skip cleanly on hardware without the keyboard backlight
# rather than crash-looping. (This image builds a kbd-only asahi-brightnessd;
# the display backlight is left manual.)
grep -Eq '^ConditionPathExists=/sys/class/leds/kbd_backlight/max_brightness' "$UNIT_FILE" \
    || fail "asahi-brightnessd unit is missing the kbd-backlight ConditionPathExists"
# Non-hardware smoke test: upstream has no --help/offline mode, so the only
# build-safe check is that the daemon FAILS CLEANLY (non-zero exit, no hang)
# when the kbd backlight is absent — which is the container-build case.
# Never run this if a real kbd_backlight exists: a build host with live
# Asahi hardware must not have its brightness written by the test.
if [[ ! -e /sys/class/leds/kbd_backlight ]]; then
    set +e
    timeout 10 "$BRIGHTNESSD" >/dev/null 2>&1
    _brightnessd_rc=$?
    set -e
    if [[ "$_brightnessd_rc" -eq 0 || "$_brightnessd_rc" -eq 124 ]]; then
        fail "asahi-brightnessd did not fail cleanly without hardware (exit $_brightnessd_rc)"
    fi
fi

# 3d) GNOME Keyring daemon must be enabled in the USER session so the keyring
#     (pkcs11 + secrets) starts for every user at login without a manual
#     `systemctl --user enable --now gnome-keyring-daemon.socket`. Fedora 44's
#     socket unit has [Install] WantedBy=sockets.target, so the enablement
#     symlink belongs in /etc/systemd/user/sockets.target.wants/.
GNOME_KEYRING_SOCKET=gnome-keyring-daemon.socket
if [[ ! -f "/usr/lib/systemd/user/$GNOME_KEYRING_SOCKET" ]]; then
    fail "gnome-keyring user socket unit missing: $GNOME_KEYRING_SOCKET"
fi
if [[ ! -L "/etc/systemd/user/sockets.target.wants/$GNOME_KEYRING_SOCKET" ]] \
   || [[ "$(readlink "/etc/systemd/user/sockets.target.wants/$GNOME_KEYRING_SOCKET")" \
         != "/usr/lib/systemd/user/$GNOME_KEYRING_SOCKET" ]]; then
    fail "gnome-keyring socket is not enabled (missing or wrong sockets.target.wants symlink)"
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
# The helper must hand off through the namespaced ASAHI_ATOMIC_DTBS override and
# must NOT rely on exporting plain DTBS (a persistent /etc config could silently
# clobber an exported plain DTBS).
if ! grep -q 'export ASAHI_ATOMIC_DTBS=' "$HELPER"; then
    fail "m1n1 helper does not export the ASAHI_ATOMIC_DTBS namespaced override"
fi
if grep -Eq '^[[:space:]]*export[[:space:]]+DTBS=' "$HELPER" \
   || grep -Eq '^[[:space:]]*export[[:space:]]+DTBS$' "$HELPER"; then
    fail "m1n1 helper still exports the plain DTBS variable (must use ASAHI_ATOMIC_DTBS)"
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

# 10) Behavioral conflict test: a stock/default config setting a stale `DTBS`
#     must NOT override the deployment-aware ASAHI_ATOMIC_DTBS value.
#
#     Approach: copy the patched /usr/bin/update-m1n1 and redirect only its
#     hardcoded config-source path and throwaway m1n1config to temp files, so the
#     real config-sourcing -> override-application ordering is exercised verbatim
#     while the ESP is never mounted/written. We then set a DELIBERATELY WRONG
#     DTBS in the fake config, provide the correct deployment DTB dir through
#     ASAHI_ATOMIC_DTBS, point TARGET at a temp payload, and assert the payload
#     contains the correct DTBs and not the stale config path.
_ov_test_root="$(mktemp -d)"
_ov_cleanup() { rm -rf "${_ov_test_root:-}"; }
trap _ov_cleanup EXIT
mkdir -p "$_ov_test_root/apple"

# A copy of the real, already-patched script.
_ov_script="$_ov_test_root/update-m1n1"
cp "$UPDATE_M1N1" "$_ov_script"
chmod +x "$_ov_script"

# Redirect the stock config-source line so the copy sources OUR temp fake default
# (with the deliberately wrong DTBS) instead of the real /etc, and redirect the
# throwaway per-run m1n1 config so nothing touches /run or the ESP. Only these
# two I/O paths are redirected; the config-sourcing -> override -> DTBS-check
# ordering and the override application run verbatim.
sed -i \
    -e "s|^\[ -e /etc/sysconfig/update-m1n1 \] \&\& \. /etc/sysconfig/update-m1n1\$|[ -e \"\$_ov_fake_default\" ] \&\& . \"\$_ov_fake_default\"|" \
    -e 's|^m1n1config=/run/m1n1\.conf$|m1n1config="$ASAHI_ATOMIC_TMP"/m1n1.conf|' \
    "$_ov_script"

# Fake functions.sh next to the copy (update-m1n1 sources $(dirname $0)/functions.sh)
cat > "$_ov_test_root/functions.sh" <<'EOF'
#!/bin/sh
warn()  { echo "WARN: $*" >&2; }
info()  { echo "INFO: $*" >&2; }
mount_sys_esp() { mkdir -p "$1"; }
EOF

# 1) Fake default config sets a deliberately WRONG, stale DTBS.
printf 'DTBS=/definitely/wrong/stale-dtb\n' > "$_ov_test_root/fake-default"
# 2) Correct deployment-aware DTB dir (as the helper would resolve).
printf 'CORRECT-DEPLOYMENT-DTB\n'   > "$_ov_test_root/apple/t6MARKER.dtb"
printf 'CORRECT-DEPLOYMENT-DTB2\n'  > "$_ov_test_root/apple/t81MARKER.dtb"

# 3) Minimal m1n1 / U-Boot source payloads for the copy.
printf 'M1N1PAYLOAD\n'  > "$_ov_test_root/m1n1.bin"
printf 'UBOOTNODTB\n'   > "$_ov_test_root/u-boot-nodtb.bin"

# 4) Invoke the copied, patched logic with the conflicting config and the
#    deployment override.
_ov_out="$_ov_test_root/boot.bin"
if ! ( cd "$_ov_test_root" && \
       ASAHI_ATOMIC_TMP="$_ov_test_root" \
       _ov_fake_default="$_ov_test_root/fake-default" \
       M1N1="$_ov_test_root/m1n1.bin" \
       U_BOOT="$_ov_test_root/u-boot-nodtb.bin" \
       TARGET="$_ov_out" \
       ASAHI_ATOMIC_DTBS="$_ov_test_root" \
       sh "$_ov_script" >/dev/null 2>&1 ); then
    fail "patched update-m1n1 conflicting-config behavioral run failed"
fi
# 5) The effective DTBS must be the deployment dir (payload contains its DTBs).
if ! grep -q 'CORRECT-DEPLOYMENT-DTB' "$_ov_out"; then
    fail "ASAHI_ATOMIC_DTBS override lost: payload does not contain deployment DTB"
fi
if grep -Eq 'definitely/wrong|/stale-dtb' "$_ov_out"; then
    fail "stale config DTBS won: payload contains wrong/stale DTB path"
fi
trap - EXIT
_ov_cleanup

echo "Image validation passed."
