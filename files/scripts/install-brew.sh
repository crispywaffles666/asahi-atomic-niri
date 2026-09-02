#!/usr/bin/env bash
set -euo pipefail

# Based on BlueBuild's Apache-2.0 brew module. Pin the installer, turn off its
# updates and metrics, and let uupd handle updates.
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

# Brew's installer needs a container mark and a working /home link. tmpfiles
# rebuilds both /var paths at boot.
mkdir -p /var/home /var/roothome
mkdir -p /home/linuxbrew
touch /.dockerenv
NONINTERACTIVE=1 CI=1 HOME=/home/linuxbrew /usr/bin/bash /tmp/brew-install
rm -f /.dockerenv /tmp/brew-install

# Store Brew under read-only /usr; brew-setup copies it to writable /var.
tar --zstd -cf /tmp/homebrew-tarball.tar.zst /home/linuxbrew/.linuxbrew
rm -rf /home/linuxbrew/.linuxbrew
rm -rf /var/home/linuxbrew/.cache
mkdir -p /usr/share/homebrew/
tar -I zstd --preserve-permissions -xf /tmp/homebrew-tarball.tar.zst -C /usr/share/homebrew/
chown -R 1000:1000 /usr/share/homebrew/
rm -f /tmp/homebrew-tarball.tar.zst

echo "Homebrew staged in image at /usr/share/homebrew"
