#!/usr/bin/bash
# Overpass Nerd Font is unavailable in Fedora repos, COPR, and the official
# nerd-fonts release zips (only Arch builds it from the nerd-fonts source
# tree). Fetch the pinned Arch package at build time and extract the fonts.
# Pinned to the exact version + sha256 of the package on the reference
# machine (otf-overpass-nerd 3.4.0-2).
set -euxo pipefail

PKG_VERSION="3.4.0-2"
PKG_SHA256="38c2396c7014a1708f3251186a565867b15e401cdd6397865f98e1a5527b40e9"
PKG_URL="https://archive.archlinux.org/packages/o/otf-overpass-nerd/otf-overpass-nerd-${PKG_VERSION}-any.pkg.tar.zst"

curl -fSL --retry 3 -o /tmp/overpass-nerd.pkg.tar.zst "$PKG_URL"
echo "${PKG_SHA256}  /tmp/overpass-nerd.pkg.tar.zst" | sha256sum -c -

mkdir -p /usr/share/fonts/OTF/overpass-nerd
zstdcat /tmp/overpass-nerd.pkg.tar.zst \
    | tar -x -C /usr/share/fonts/OTF/overpass-nerd --strip-components=4 --wildcards 'usr/share/fonts/OTF/*.otf'

fc-cache -f /usr/share/fonts/OTF/overpass-nerd
rm -f /tmp/overpass-nerd.pkg.tar.zst
