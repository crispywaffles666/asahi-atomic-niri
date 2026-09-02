#!/usr/bin/bash
# Install the pinned GTK and icon themes into an isolated build stage.
set -euxo pipefail

readonly GRAPHITE_COMMIT="78562a21fce831c34cf890d5155788884e37b7f3"
readonly GRAPHITE_SHA256="c86fa050b45127553e6233595162d68a18030ffb1272feae1f8a2a4e488dcec1"
readonly GRAPHITE_URL="https://github.com/vinceliuice/Graphite-gtk-theme/archive/${GRAPHITE_COMMIT}.tar.gz"

readonly DRACULA_ICONS_COMMIT="de2a8edd94608ba0ac4dcf5a187af0ffaa511ebc"
readonly DRACULA_ICONS_SHA256="51db7832983249a6d296154fdb7afab7c51c32ac8813bc5bf73ee89a3e1ebb36"
readonly DRACULA_ICONS_URL="https://github.com/m4thewz/dracula-icons/archive/${DRACULA_ICONS_COMMIT}.tar.gz"

readonly GRAPHITE_THEME_DIR="/usr/share/themes/Graphite-purple-Dark-dracula"
readonly DRACULA_ICONS_DIR="/usr/share/icons/dracula-icons-main"

work_dir="$(mktemp -d)"
cleanup() {
    rm -rf "$work_dir"
}
trap cleanup EXIT

download() {
    local url="$1"
    local checksum="$2"
    local output="$3"

    curl --fail --location --retry 3 --retry-delay 2 --output "$output" "$url"
    printf '%s  %s\n' "$checksum" "$output" | sha256sum --check -
}

graphite_archive="$work_dir/graphite.tar.gz"
graphite_source="$work_dir/graphite"
download "$GRAPHITE_URL" "$GRAPHITE_SHA256" "$graphite_archive"
mkdir -p "$graphite_source"
tar --extract --gzip --file "$graphite_archive" \
    --directory "$graphite_source" --strip-components=1

rm -rf "$GRAPHITE_THEME_DIR" "${GRAPHITE_THEME_DIR}-hdpi" "${GRAPHITE_THEME_DIR}-xhdpi"
(
    cd "$graphite_source"
    ./install.sh \
      --dest /usr/share/themes \
      --theme purple \
      --color dark \
      --tweaks dracula rimless normal
)
install -Dm0644 "$graphite_source/LICENSE" \
    /usr/share/licenses/Graphite-gtk-theme/LICENSE

dracula_archive="$work_dir/dracula-icons.tar.gz"
download "$DRACULA_ICONS_URL" "$DRACULA_ICONS_SHA256" "$dracula_archive"
rm -rf "$DRACULA_ICONS_DIR"
mkdir -p "$DRACULA_ICONS_DIR"
tar --extract --gzip --file "$dracula_archive" \
    --directory "$DRACULA_ICONS_DIR" --strip-components=1

# Upstream references GPL-3.0 from README.md but does not ship LICENSE.md at
# this revision, so retain that verbatim licensing notice alongside the theme.
install -Dm0644 "$DRACULA_ICONS_DIR/README.md" \
    /usr/share/licenses/dracula-icons/README.md

gtk-update-icon-cache "$DRACULA_ICONS_DIR"
