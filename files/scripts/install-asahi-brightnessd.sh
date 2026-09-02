#!/usr/bin/bash
# Build and install craig-miller/asahi-brightnessd from pinned upstream source.
#
# asahi-brightnessd reads the Apple Silicon AOP ALS (aop-sensors-als, IIO
# sysfs) and drives the KBD backlight (/sys/class/leds/kbd_backlight) with
# manual-override detection. Stock upstream also drives the DISPLAY backlight
# (/sys/class/backlight/apple-panel-bl), which this image deliberately drops:
# automatic panel writes would make Noctalia pop a brightness OSD on every
# ambient-light adjustment. The kbd-only behavior is applied here via a
# checksum-locked patch (files/patches/asahi-brightnessd-kbdonly.patch).
# Upstream ships no Fedora RPM and no systemd unit, so we build the MIT-licensed
# C source at image build time and supply our own unit
# (files/system/usr/lib/systemd/system/).
#
# Pinned to the exact upstream commit (not main) and checksum-locked ahead of
# time; the codeload tar.gz of a git SHA is deterministic.
set -euxo pipefail

# The upstream commit this image is built from. Do not move this to a moving
# ref: the source and behavior must stay reproducible across image rebuilds.
UPSTREAM_REPO="craig-miller/asahi-brightnessd"
UPSTREAM_COMMIT="c8038a3562b79309932463966237d368a421d292"
TARBALL_SHA256="bf133196130310e22ba1db623a03039b9663c2b34b2cfce7251b3ccf726bdd89"
TARBALL_URL="https://codeload.github.com/${UPSTREAM_REPO}/tar.gz/${UPSTREAM_COMMIT}"

# The Makefile needs a working cc; gcc/make/patch are already installed by the
# Containerfile (and kept there for brew/other build-time steps).
for dep in gcc make patch; do
    command -v "$dep" >/dev/null 2>&1 || {
        echo "ERROR: missing '$dep'; install it in the Containerfile first" >&2
        exit 1
    }
done

echo "Downloading asahi-brightnessd (pinned ${UPSTREAM_COMMIT:0:12})..."
curl -fSL --retry 5 -o /tmp/asahi-brightnessd.tar.gz "$TARBALL_URL"
echo "${TARBALL_SHA256}  /tmp/asahi-brightnessd.tar.gz" | sha256sum -c -

mkdir -p /tmp/asahi-brightnessd-src
tar -xzf /tmp/asahi-brightnessd.tar.gz \
    -C /tmp/asahi-brightnessd-src --strip-components=1

# Compatibility gate: building/vendoring upstream requires a compatible
# (permissive) license. Upstream is MIT; fail the build if that ever changes.
if ! grep -qi 'MIT License' /tmp/asahi-brightnessd-src/LICENSE; then
    echo "ERROR: asahi-brightnessd LICENSE no longer matches MIT" >&2
    exit 1
fi

# Apply the image's kbd-only patch: stock asahi-brightnessd drives BOTH the
# display and keyboard backlights, which makes Noctalia pop a brightness OSD
# on every ambient-light adjustment. This image deliberately drops the screen
# channel (files/patches/asahi-brightnessd-kbdonly.patch) so the panel is left
# fully manual and Noctalia shows no OSD for automatic changes. The patch is
# checksum-locked to the same pinned upstream commit; if upstream drifts at
# this commit the patch fails to apply and the build stops loudly.
PATCH_SHA256="2443d8141cf8a9077a472c037265da71010b1a414ec9c65825272ac2489b4949"
echo "${PATCH_SHA256}  /tmp/asahi-brightnessd-kbdonly.patch" | sha256sum -c -
patch -p1 -d /tmp/asahi-brightnessd-src < /tmp/asahi-brightnessd-kbdonly.patch

# Upstream's Makefile installs to /usr/sbin/asahi-brightnessd
# (PREFIX=/usr, SBIN=$(PREFIX)/sbin).
make -C /tmp/asahi-brightnessd-src
make -C /tmp/asahi-brightnessd-src install

if [[ ! -x /usr/sbin/asahi-brightnessd ]]; then
    echo "ERROR: /usr/sbin/asahi-brightnessd missing after make install" >&2
    exit 1
fi

# Strip the build-time symbol table; the image has no use for it.
command -v strip >/dev/null 2>&1 && strip /usr/sbin/asahi-brightnessd

# Remove the build tree and tarball; the runtime image only needs the binary.
rm -rf /tmp/asahi-brightnessd-src /tmp/asahi-brightnessd.tar.gz

echo "Installed /usr/sbin/asahi-brightnessd"