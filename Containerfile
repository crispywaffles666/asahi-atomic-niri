FROM quay.io/fedora-asahi-remix-atomic-desktops/base-atomic:44

# Brave cannot unpack through the base image's dangling /opt link. A real /opt
# also keeps browser files out of /var, as bootc lint requires.
RUN rm -rf /opt

COPY files/dnf/*.repo /etc/yum.repos.d/

RUN dnf config-manager addrepo --from-repofile=https://github.com/terrapkg/subatomic-repos/raw/main/terra.repo && \
    dnf config-manager addrepo --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo && \
    dnf install -y https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-44.noarch.rpm

RUN dnf install -y \
    niri xwayland-satellite greetd tuigreet alacritty \
    xdg-desktop-portal-gnome xdg-desktop-portal-gtk gnome-keyring gnome-keyring-pam nautilus \
    noctalia ghostty satty \
    brightnessctl playerctl inotify-tools wl-clipboard wtype \
    # This exposes sensor checks; asahi-brightnessd reads sysfs itself.
    iio-sensor-proxy \
    pavucontrol cava seahorse xterm zsh bat micro geany \
    ripgrep stow yazi starship overpass-fonts \
    libnotify xdg-utils \
    # The bundled icon theme needs its index built below.
    gtk-update-icon-cache \
    # auto-fullwidth-dp3.sh reads `niri msg --json` output.
    jq \
    fastfetch \
    pulseaudio-utils \
    brave-origin \
    gcc make patch \
    tailscale \
    uupd \
    keyd \
    distrobox \
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
    && dnf clean all

# Keep shared themes under /usr so all users get the same read-only files.
COPY files/themes/ /usr/share/themes/
COPY files/icons/ /usr/share/icons/
RUN gtk-update-icon-cache /usr/share/icons/dracula-icons-main

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

# brew-setup copies this read-only tree to /var on first boot; uupd updates it.
COPY files/scripts/install-brew.sh /tmp/install-brew.sh
RUN chmod +x /tmp/install-brew.sh && \
    /tmp/install-brew.sh && \
    rm /tmp/install-brew.sh

RUN printf 'HOMEBREW_NO_ANALYTICS=%s\n' 1 >> /etc/environment

COPY files/scripts/install-overpass-nerd.sh /tmp/install-overpass-nerd.sh
RUN chmod +x /tmp/install-overpass-nerd.sh && \
    /tmp/install-overpass-nerd.sh && \
    rm /tmp/install-overpass-nerd.sh

# Fedora has no asahi-brightnessd package, so build the pinned source.
COPY files/patches/asahi-brightnessd-kbdonly.patch /tmp/asahi-brightnessd-kbdonly.patch
COPY files/scripts/install-asahi-brightnessd.sh /tmp/install-asahi-brightnessd.sh
RUN chmod +x /tmp/install-asahi-brightnessd.sh && \
    /tmp/install-asahi-brightnessd.sh && \
    rm /tmp/install-asahi-brightnessd.sh

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
