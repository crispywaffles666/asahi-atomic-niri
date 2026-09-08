# One Fedora release drives every stage: the disposable builders must match
# the final Asahi base image's userspace (asahi-brightnessd is a compiled
# binary copied into it). Renovate moves this ARG through the Asahi base
# dependency; standalone fedora build-image bumps are disabled in
# .github/renovate.json5 so the builders can never outrun the base.
ARG FEDORA_RELEASE=44
# CI passes the already-verified upstream digest, never re-resolves its tag.
ARG BASE_IMAGE=quay.io/fedora-asahi-remix-atomic-desktops/base-atomic:${FEDORA_RELEASE}
ARG BUILDER_IMAGE=registry.fedoraproject.org/fedora:${FEDORA_RELEASE}

# Universal Blue's maintained Homebrew component: a pre-built tarball,
# first-boot setup service, and shell integration, published for both
# amd64 and aarch64. Renovate bumps the pinned digest (.github/renovate.json5).
ARG BREW_IMAGE=ghcr.io/ublue-os/brew:latest@sha256:d52b3f578f01623636aff534291b0bd8ff0a0244ef225bf51aecb5fa05a137af
FROM ${BREW_IMAGE} AS brew

# Union of every build-only tool the artifact stages need. None of it crosses
# a COPY --from boundary into the final image; validate-image.sh rejects
# sassc/gcc/make/patch if they ever do.
FROM ${BUILDER_IMAGE} AS builder-base

RUN dnf install -y --setopt=install_weak_deps=False \
    bash coreutils curl gcc gzip make patch sassc sed tar gtk-update-icon-cache zstd fontconfig && \
    dnf clean all

# Theme generation and archive tooling stay in this disposable stage.
FROM builder-base AS theme-builder

COPY files/scripts/install-themes.sh /tmp/install-themes.sh
RUN chmod +x /tmp/install-themes.sh && \
    /tmp/install-themes.sh

# gcc/make/patch exist only to compile asahi-brightnessd; keep them out of the
# final image the same way the theme stage keeps sassc out.
FROM builder-base AS brightnessd-builder

COPY files/patches/asahi-brightnessd-kbdonly.patch /tmp/asahi-brightnessd-kbdonly.patch
COPY files/scripts/install-asahi-brightnessd.sh /tmp/install-asahi-brightnessd.sh
RUN chmod +x /tmp/install-asahi-brightnessd.sh && \
    /tmp/install-asahi-brightnessd.sh

FROM builder-base AS font-builder
COPY files/scripts/install-overpass-nerd.sh /tmp/install-overpass-nerd.sh
RUN bash /tmp/install-overpass-nerd.sh

# CI persists only these pinned artifact stages in the registry build cache.
# Mutable RPM transactions in the final image always run on the fresh runner.
FROM scratch AS artifacts
COPY --from=theme-builder /usr/share/themes/Graphite-purple-Dark-dracula /usr/share/themes/Graphite-purple-Dark-dracula
COPY --from=theme-builder /usr/share/icons/dracula-icons-main /usr/share/icons/dracula-icons-main
COPY --from=theme-builder /usr/share/licenses/Graphite-gtk-theme /usr/share/licenses/Graphite-gtk-theme
COPY --from=theme-builder /usr/share/licenses/dracula-icons /usr/share/licenses/dracula-icons
COPY --from=brightnessd-builder /usr/sbin/asahi-brightnessd /usr/sbin/asahi-brightnessd
COPY --from=brightnessd-builder /usr/share/licenses/asahi-brightnessd /usr/share/licenses/asahi-brightnessd
COPY --from=font-builder /usr/share/fonts/OTF/overpass-nerd /usr/share/fonts/OTF/overpass-nerd

FROM ${BASE_IMAGE}

# Brave cannot unpack through the base image's dangling /opt link. A real /opt
# also keeps browser files out of /var, as bootc lint requires.
RUN rm -rf /opt

# Every repo definition is vendored under files/dnf; no mutable remote .repo
# files are fetched during the build.
COPY files/dnf/*.repo /etc/yum.repos.d/

# The RPM Fusion release RPM follows the same pin-and-verify pattern as the
# builder stages' source tarballs. The known SHA is for the FEDORA_RELEASE
# build above; bump both together.
ARG FEDORA_RELEASE
RUN curl -fSL --retry 3 --output /tmp/rpmfusion-free-release.rpm \
        "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_RELEASE}.noarch.rpm" && \
    echo "8af2dbb02e3a72f0961ec79cf1ea3f350719cb830b0f99f59e939389feb34b1c  /tmp/rpmfusion-free-release.rpm" | sha256sum --check - && \
    dnf install -y /tmp/rpmfusion-free-release.rpm && \
    rm /tmp/rpmfusion-free-release.rpm

COPY files/scripts/hardware-package-set.sh /tmp/hardware-package-set.sh
RUN bash /tmp/hardware-package-set.sh snapshot /tmp/asahi-hardware.before && \
    dnf install -y \
    niri xwayland-satellite greetd tuigreet alacritty \
    xdg-desktop-portal-gnome xdg-desktop-portal-gtk gnome-keyring gnome-keyring-pam nautilus \
    noctalia ghostty satty \
    brightnessctl playerctl inotify-tools wl-clipboard wtype \
    # This exposes sensor checks; asahi-brightnessd reads sysfs itself.
    iio-sensor-proxy \
    pavucontrol cava seahorse xterm zsh bat micro geany \
    ripgrep stow yazi starship overpass-fonts \
    libnotify xdg-utils \
    # auto-fullwidth-dp3.sh reads `niri msg --json` output.
    jq \
    fastfetch \
    pulseaudio-utils \
    brave-origin \
    tailscale \
    uupd \
    keyd \
    distrobox \
    # brew-setup.service unpacks the brew tarball with `tar --zstd` at boot.
    zstd \
    # The first-login app setup and uupd both need Flatpak on the host.
    flatpak \
    # The base image lacks desktop tools for disks, print, Bluetooth, and files.
    udisks2 \
    gvfs gvfs-mtp gvfs-archive gvfs-fuse \
    gnome-disk-utility \
    cups cups-client \
    bluez blueman \
    power-profiles-daemon \
    file-roller file-roller-nautilus evince eog \
    # RPM Fusion's full FFmpeg supplies H.264/H.265 software decode and
    # libx264/libx265 encoding. Do not replace Asahi's hardware stack.
    ffmpeg ffmpeg-libs x264-libs x265-libs ffmpegthumbnailer \
    gstreamer1-plugin-libav \
    gstreamer1-plugins-base gstreamer1-plugins-base-tools \
    gstreamer1-plugins-good \
    gstreamer1-plugins-bad-free gstreamer1-plugins-ugly-free \
    --allowerasing \
    --exclude="swaylock,waybar,fuzzel,mesa-*-freeworld" \
    && bash /tmp/hardware-package-set.sh check /tmp/asahi-hardware.before \
    && rm /tmp/hardware-package-set.sh /tmp/asahi-hardware.before \
    && dnf clean all

# Keep shared themes under /usr so all users get the same read-only files.
# Only generated artifacts leave the builder; source and sassc stay behind.
RUN rm -rf /usr/share/themes/Graphite-purple-Dark-dracula \
           /usr/share/icons/dracula-icons-main
COPY --from=artifacts / /
RUN fc-cache -f /usr/share/fonts/OTF/overpass-nerd

COPY files/system/ /

# COPY does not keep these scripts' execute bits.
RUN chmod +x /usr/libexec/asahi-niri/config-flatpaks.sh && \
    chmod +x /usr/libexec/asahi-atomic-niri/update-m1n1-helper.sh

# OSTree gives /usr files a zero timestamp, which breaks `gzip -c` in
# update-m1n1. The patch also makes the booted tree override stale /etc settings.
# It stops the build if the stock script no longer has the known shape.
# See https://github.com/AsahiLinux/asahi-scripts/issues/71.
COPY files/scripts/patch-update-m1n1.sh /tmp/patch-update-m1n1.sh
RUN chmod +x /tmp/patch-update-m1n1.sh && \
    /tmp/patch-update-m1n1.sh && \
    rm /tmp/patch-update-m1n1.sh

# Check the installed U-Boot without writing to the ESP.
RUN /usr/libexec/asahi-atomic-niri/update-m1n1-helper.sh gzip-check

# Refresh m1n1 only after the new tree has booted.
RUN systemctl enable asahi-atomic-niri-update-m1n1.service

# The brew component ships the tarball and a maintained brew-setup.service
# that unpacks it to /home/linuxbrew on first boot; uupd updates it after.
# This COPY must precede the `systemctl enable brew-setup.service` below.
COPY --from=brew /system_files/ /

# Let uupd stage OS updates without rebooting. Mask the base image's other
# update timers so they cannot apply an update or reboot on their own.
RUN systemctl enable greetd.service && \
    systemctl enable tailscaled.service && \
    systemctl enable keyd.service && \
    systemctl enable asahi-brightnessd.service && \
    systemctl enable uupd.timer && \
    systemctl enable flathub-setup.service && \
    systemctl enable brew-setup.service && \
    systemctl enable cups.socket && \
    systemctl enable bluetooth.service && \
    systemctl enable power-profiles-daemon.service && \
    systemctl mask bootc-fetch-apply-updates.timer && \
    systemctl mask rpm-ostreed-automatic.timer && \
    systemctl set-default graphical.target

RUN printf 'HOMEBREW_NO_ANALYTICS=%s\n' 1 >> /etc/environment

# These base-image overrides name GNOME parts that this image removes.
RUN rm -f /usr/share/glib-2.0/schemas/00_org.gnome.shell.gschema.override \
         /usr/share/glib-2.0/schemas/org.gnome.shell.gschema.override \
         /usr/share/glib-2.0/schemas/org.gnome.login-screen.gschema.override \
         /usr/share/glib-2.0/schemas/10_org.gnome.desktop.screensaver.fedora.gschema.override \
         /usr/share/glib-2.0/schemas/org.gnome.Ptyxis.fedora.gschema.override \
         /usr/share/glib-2.0/schemas/zz0-0*.gschema.override && \
    glib-compile-schemas --strict /usr/share/glib-2.0/schemas

# GNOME search has no work to do on this desktop.
RUN for u in /usr/lib/systemd/user/localsearch*.service; do \
        [ -f "$u" ] && ln -sf /dev/null "/etc/systemd/user/$(basename "$u")"; \
    done

# bootc mounts /boot read-only, so this unit fails at each login. Asahi does not
# read its menu-hiding flag; its m1n1 refresh tracks success on its own.
RUN ln -sf /dev/null /etc/systemd/user/grub-boot-success.timer

COPY files/scripts/validate-image.sh /tmp/validate-image.sh
RUN chmod +x /tmp/validate-image.sh && \
    /tmp/validate-image.sh && \
    rm /tmp/validate-image.sh

# Package hooks leave mutable files that bootc lint rejects. tmpfiles rebuilds
# the needed paths at boot.
RUN rm -rf \
    /var/log/dnf5.log* \
    /var/cache/libdnf5 \
    /var/cache/ldconfig/aux-cache \
    /var/lib/dnf \
    /var/lib/greetd/.config \
    /run/dnf \
    /run/selinux-policy \
    /tmp/*

RUN bootc container lint --fatal-warnings
