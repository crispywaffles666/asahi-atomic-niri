#!/usr/bin/bash
# Upstream also dims the screen, which makes Noctalia show an OSD on each light
# change. Build a pinned, patched copy that controls only the keyboard light.
set -euxo pipefail

# Pin both source and hash so rebuilds use the same code.
UPSTREAM_REPO="craig-miller/asahi-brightnessd"
UPSTREAM_COMMIT="c8038a3562b79309932463966237d368a421d292"
TARBALL_SHA256="bf133196130310e22ba1db623a03039b9663c2b34b2cfce7251b3ccf726bdd89"
TARBALL_URL="https://codeload.github.com/${UPSTREAM_REPO}/tar.gz/${UPSTREAM_COMMIT}"

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

# Stop if upstream changes the license.
if ! grep -qi 'MIT License' /tmp/asahi-brightnessd-src/LICENSE; then
    echo "ERROR: asahi-brightnessd LICENSE no longer matches MIT" >&2
    exit 1
fi

# Hash the patch too, so a source or patch drift stops the build.
PATCH_SHA256="5fe7615c3c43f899972c9b6cc946bbc5e60f014b29aea5dd6bbedf7f147baeef"
echo "${PATCH_SHA256}  /tmp/asahi-brightnessd-kbdonly.patch" | sha256sum -c -
patch -p1 -d /tmp/asahi-brightnessd-src < /tmp/asahi-brightnessd-kbdonly.patch

make -C /tmp/asahi-brightnessd-src
make -C /tmp/asahi-brightnessd-src install

if [[ ! -x /usr/sbin/asahi-brightnessd ]]; then
    echo "ERROR: /usr/sbin/asahi-brightnessd missing after make install" >&2
    exit 1
fi

command -v strip >/dev/null 2>&1 && strip /usr/sbin/asahi-brightnessd

rm -rf /tmp/asahi-brightnessd-src /tmp/asahi-brightnessd.tar.gz

echo "Installed /usr/sbin/asahi-brightnessd"
