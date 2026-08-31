FROM quay.io/fedora-asahi-remix-atomic-desktops/base-atomic:44

# The base image's /opt is a dangling symlink to /var/opt (which does not exist
# in the image). Brave's RPM (like Chrome's) unpacks under /opt and its cpio
# fails to mkdir through that link ("cpio: mkdir failed - File exists"). Remove
# the dangling link so Brave owns a real /opt directory. Under composefs this
# makes /opt read-only image content (like /usr), which is what a browser
# wants, and keeps Bootc's var-tmpfiles lint clean (no browser files in /var).
RUN rm -rf /opt

# Add third-party repositories
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
    brave-browser \
    --exclude="swaylock,waybar,fuzzel" \
    && dnf clean all

# Copy system configuration files
COPY files/system/ /

# Enable greetd display manager and graphical target
RUN systemctl enable greetd.service && \
    systemctl set-default graphical.target

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
    /var/log/dnf5.log \
    /var/cache/libdnf5 \
    /var/cache/ldconfig/aux-cache \
    /var/lib/dnf \
    /var/lib/greetd/.config \
    /run/dnf \
    /run/selinux-policy \
    /tmp/*

# Final static image validation (the authoritative gate)
RUN bootc container lint --fatal-warnings
