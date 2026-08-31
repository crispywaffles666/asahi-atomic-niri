#!/usr/bin/env bash
set -euo pipefail

# Build-time Homebrew/Linuxbrew install, ported from the BlueBuild "brew"
# module (Apache-2.0, https://github.com/blue-build/modules) with the same
# options as bazzite-niri/asahi-bluefin: direct-pull, pinned installer commit,
# analytics off, and NO auto-update/upgrade units (uupd owns that cadence).

# Brew requires gcc and zstd; the Containerfile installs them up front.
for dep in gcc zstd; do
    command -v "$dep" >/dev/null 2>&1 || {
        echo "ERROR: missing '$dep'; install it in the Containerfile first" >&2
        exit 1
    }
done

INSTALLER_COMMIT="ca0130bd52235f2fcb2bf23cfdda004bc5d250c1"

echo "Downloading Homebrew installer (pinned $INSTALLER_COMMIT)..."
curl -fLsS --retry 5 --create-dirs \
    "https://raw.githubusercontent.com/Homebrew/install/${INSTALLER_COMMIT}/install.sh" \
    -o /tmp/brew-install
chmod +x /tmp/brew-install

# The installer skips its root guard only when it detects a container, and it
# must not prompt. HOME points at the build-time scratch under /home, which we
# repack into the image below. /home is a symlink to /var/home, which does not
# exist in the build container; create it so the symlink resolves (as the
# blue-build brew module does). Both dirs are covered by tmpfiles at boot.
mkdir -p /var/home /var/roothome
mkdir -p /home/linuxbrew
touch /.dockerenv
NONINTERACTIVE=1 CI=1 HOME=/home/linuxbrew /usr/bin/bash /tmp/brew-install
rm -f /.dockerenv /tmp/brew-install

# Repack the brew install as image-owned, read-only content under /usr/share.
# At first boot brew-setup.service copies it into /var/home/linuxbrew (the
# mutable, per-deployment user home that Homebrew actually runs from).
tar --zstd -cf /tmp/homebrew-tarball.tar.zst /home/linuxbrew/.linuxbrew
rm -rf /home/linuxbrew/.linuxbrew
# Remove build-time brew cache residue; the runtime cache is /var/cache/homebrew
# (created by homebrew.conf tmpfiles).
rm -rf /var/home/linuxbrew/.cache
mkdir -p /usr/share/homebrew/
tar -I zstd --preserve-permissions -xf /tmp/homebrew-tarball.tar.zst -C /usr/share/homebrew/
chown -R 1000:1000 /usr/share/homebrew/
rm -f /tmp/homebrew-tarball.tar.zst

echo "Homebrew staged in image at /usr/share/homebrew"
