#!/usr/bin/bash
# Preserve the exact hardware stack supplied by the Asahi base. A deliberate
# stack change needs a reviewed adjustment, not an unnoticed --allowerasing.
set -euo pipefail
snapshot() {
    rpm -qa --qf '%{NAME}\t%{EPOCHNUM}:%{VERSION}-%{RELEASE}.%{ARCH}\n' | \
        awk -F '\t' '$1 ~ /^(kernel|mesa|asahi|m1n1|uboot|u-boot|dracut|linux-firmware|alsa-ucm|speakersafetyd)/' | \
        LC_ALL=C sort
}
case ${1:-} in
    snapshot) snapshot > "$2" ;;
    check)
        current=$(mktemp)
        trap 'rm -f "$current"' EXIT
        snapshot > "$current"
        if ! diff -u "$2" "$current"; then
            echo 'ERROR: installation changed the base hardware package set' >&2
            exit 1
        fi
        ;;
    *) echo "usage: $0 snapshot|check FILE" >&2; exit 2 ;;
esac
