FROM quay.io/fedora-asahi-remix-atomic-desktops/base-atomic:44

# The base image's /opt is a dangling symlink to /var/opt (which does not exist
# in the image). Brave's RPM (like Chrome's) unpacks under /opt and its cpio
# fails to mkdir through that link ("cpio: mkdir failed - File exists"). Remove
# the dangling link so Brave owns a real /opt directory. Under composefs this
# makes /opt read-only image content (like /usr), which is what a browser
# wants, and keeps Bootc's var-tmpfiles lint clean (no browser files in /var).
RUN rm -rf /opt

# Add third-party repositories (local .repo files: tailscale, uupd COPR)
COPY files/dnf/*.repo /etc/yum.repos.d/

# Add remaining remote repositories
RUN dnf config-manager addrepo --from-repofile=https://github.com/terrapkg/subatomic-repos/raw/main/terra.repo && \
    dnf config-manager addrepo --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo

# Install niri desktop stack
RUN dnf install -y \
    niri xwayland-satellite greetd tuigreet alacritty \
    xdg-desktop-portal-gnome xdg-desktop-portal-gtk gnome-keyring nautilus \
    noctalia ghostty satty \
    brightnessctl playerctl inotify-tools wl-clipboard wtype \
    pavucontrol cava seahorse xterm zsh bat micro geany \
    ripgrep stow yazi starship overpass-fonts \
    libnotify xdg-utils \
    fastfetch \
    pulseaudio-utils \
    brave-origin \
    gcc make patch \
    tailscale \
    uupd \
    # keyd: system-wide key remapping daemon (alternateved/keyd COPR).
    keyd \
    # Containerized dev environments. distrobox is a wrapper around podman,
    # which the base-atomic image already ships (minimal-plus manifest).
    distrobox \
    # Flatpak runtime + a system Flathub remote (added at first boot by
    # flathub-setup.service). Explicit so the per-user flatpak bootstrap and
    # uupd's flatpak module have a guaranteed base to work on.
    flatpak \
    # "Boring desktop plumbing" the minimal base-atomic image does not ship:
    # mobile/removable-storage + archive mounting via gvfs, disk management,
    # printing, Bluetooth, CPU power profiles, archives, PDF and image viewers.
    udisks2 \
    gvfs gvfs-mtp gvfs-archive gvfs-fuse \
    gnome-disk-utility \
    cups cups-client \
    bluez blueman \
    power-profiles-daemon \
    file-roller file-roller-nautilus evince eog \
    # Host-native multimedia codecs (software decode) for the common codecs:
    # H.264/HEVC/VP9/AV1/AAC etc. All plain Fedora "-free" plugins; we do NOT
    # override Asahi's Mesa, kernel, or firmware (Asahi's AVD/VA-API hardware
    # decode is not yet bundled upstream, so software decode is the safe win).
    ffmpeg-free \
    gstreamer1-plugins-base gstreamer1-plugins-base-tools \
    gstreamer1-plugins-good \
    gstreamer1-plugins-bad-free gstreamer1-plugins-ugly-free \
    --exclude="swaylock,waybar,fuzzel" \
    && dnf clean all

# Copy system configuration files
COPY files/system/ /

# The per-user flatpak bootstrap script ships in /usr/libexec and must be
# executable (git does not preserve the exec bit through COPY).
RUN chmod +x /usr/libexec/asahi-niri/config-flatpaks.sh && \
    chmod +x /usr/libexec/asahi-atomic-niri/update-m1n1-helper.sh

# --- Asahi Atomic boot-chain hardening ---
# 1) Fail-closed patch of the stock `update-m1n1`: OSTree canonicalizes /usr
#    files to epoch-zero mtime, which makes `gzip -c` abort (status 2, "file
#    timestamp out of range") and, under set -e, cancels the m1n1/U-Boot
#    refresh. `gzip -nc` omits the volatile header metadata and fixed the bug.
#    https://github.com/AsahiLinux/asahi-scripts/issues/71
# 2) The same patch inserts a namespaced ASAHI_ATOMIC_DTBS override that is
#    applied AFTER Fedora's update-m1n1 config is sourced but BEFORE DTBS is
#    validated/used, so a persistent /etc config setting a stale DTBS can never
#    silently replace the deployment-aware DTB directory the helper passes in.
#    The patch refuses to build unless every expected anchor exists exactly once
#    and the ordering can be proven.
COPY files/scripts/patch-update-m1n1.sh /tmp/patch-update-m1n1.sh
RUN chmod +x /tmp/patch-update-m1n1.sh && \
    /tmp/patch-update-m1n1.sh && \
    rm /tmp/patch-update-m1n1.sh

# Non-destructive proof that the patched gzip -nc invocation is safe against the
# image's installed U-Boot (writes only a temp file; never touches the ESP).
RUN /usr/libexec/asahi-atomic-niri/update-m1n1-helper.sh gzip-check

# Enable the deploy-aware m1n1 refresh (oneshot that runs only once a newly
# booted deployment reaches multi-user, then records success; idempotent).
RUN systemctl enable asahi-atomic-niri-update-m1n1.service

# Enable greetd display manager, networking/switch service, automatic updates,
# the per-user flatpak bootstrap, and the desktop plumbing services, then set the
# graphical target. CUPS and Bluetooth use socket activation (cups.socket) so they
# only start when first needed. power-profiles-daemon provides CPU performance
# profile control on Apple Silicon and is socket-activated by its own service.
#
# Automatic OS updates: only `uupd.timer` is enabled. uupd stages bootc/rpm-ostree
# updates but never reboots. To harden against any latent auto-apply/reboot
# driver shipping in the base (fail closed), explicitly mask the bootc and
# rpm-ostree automatic update timers so the *only* automatic OS update path is
# uupd (stage, no reboot). This does not touch uupd itself or Flatpak/Brew.
RUN systemctl enable greetd.service && \
    systemctl enable tailscaled.service && \
    systemctl enable keyd.service && \
    systemctl enable uupd.timer && \
    systemctl enable flathub-setup.service && \
    systemctl enable brew-setup.service && \
    systemctl enable cups.socket && \
    systemctl enable bluetooth.service && \
    systemctl enable power-profiles-daemon.service && \
    systemctl mask bootc-fetch-apply-updates.timer && \
    systemctl mask rpm-ostreed-automatic.timer && \
    systemctl set-default graphical.target

# Homebrew: stage an image-owned brew tree that brew-setup.service copies into
# /var/home/linuxbrew on first boot. uupd owns the update cadence.
COPY files/scripts/install-brew.sh /tmp/install-brew.sh
RUN chmod +x /tmp/install-brew.sh && \
    /tmp/install-brew.sh && \
    rm /tmp/install-brew.sh

# Homebrew analytics opt-out (same as Universal Blue / secureblue)
RUN printf 'HOMEBREW_NO_ANALYTICS=%s\n' 1 >> /etc/environment

# Install Overpass Nerd Font (arch-independent Arch package)
COPY files/scripts/install-overpass-nerd.sh /tmp/install-overpass-nerd.sh
RUN chmod +x /tmp/install-overpass-nerd.sh && \
    /tmp/install-overpass-nerd.sh && \
    rm /tmp/install-overpass-nerd.sh

# Clean broken gschema overrides and recompile
RUN rm -f /usr/share/glib-2.0/schemas/00_org.gnome.shell.gschema.override \
         /usr/share/glib-2.0/schemas/org.gnome.shell.gschema.override \
         /usr/share/glib-2.0/schemas/org.gnome.login-screen.gschema.override \
         /usr/share/glib-2.0/schemas/10_org.gnome.desktop.screensaver.fedora.gschema.override \
         /usr/share/glib-2.0/schemas/org.gnome.Ptyxis.fedora.gschema.override \
         /usr/share/glib-2.0/schemas/zz0-0*.gschema.override && \
    glib-compile-schemas --strict /usr/share/glib-2.0/schemas

# Mask localsearch user units (unnecessary without GNOME)
RUN for u in /usr/lib/systemd/user/localsearch*.service; do \
        [ -f "$u" ] && ln -sf /dev/null "/etc/systemd/user/$(basename "$u")"; \
    done

# Validate the final image
COPY files/scripts/validate-image.sh /tmp/validate-image.sh
RUN chmod +x /tmp/validate-image.sh && \
    /tmp/validate-image.sh && \
    rm /tmp/validate-image.sh

# Remove dnf/package build residue so bootc lint --fatal-warnings passes, matching
# the clean base image. dnf leaves logs and caches, package post-install scripts
# leave /run + /var artifacts, and the greetd home gets extra .config from the
# gnome-keyring/portal post-install (recreated where needed at boot by
# tmpfiles.d). This is standard bootc image hygiene, not validation weakening.
RUN rm -rf \
    /var/log/dnf5.log* \
    /var/cache/libdnf5 \
    /var/cache/ldconfig/aux-cache \
    /var/lib/dnf \
    /var/lib/greetd/.config \
    /run/dnf \
    /run/selinux-policy \
    /tmp/*

# Final static image validation (the authoritative gate)
RUN bootc container lint --fatal-warnings
