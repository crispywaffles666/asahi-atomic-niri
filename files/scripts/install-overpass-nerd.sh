#!/usr/bin/bash
# Only Arch ships Overpass Nerd Font. Pin its package and hash for safe rebuilds.
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
