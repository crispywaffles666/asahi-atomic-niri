#!/usr/bin/bash
# Fail-closed build-time patch for the Asahi `update-m1n1` script on Atomic.
#
# OSTree canonicalizes package-owned files under /usr to an epoch-zero mtime.
# `gzip -c` refuses to encode that (uint32 gzip timestamp range) and, under
# `gzip -c`, prints:
#
#   warning: file timestamp out of range for gzip format
#
# and exits with status 2. Because update-m1n1 runs under `set -e`, this aborts
# the m1n1/U-Boot refresh. Passing `-n` omits the volatile filename+timestamp
# header metadata (the decompressed payload is byte-identical) and avoids the
# abort.
#
# https://github.com/AsahiLinux/asahi-scripts/issues/71
#
# This script is intentionally strict ("fail closed"): it will refuse to build
# if the exact expected source line does not appear exactly once, rather than
# silently doing nothing when upstream changes the script.
set -euo pipefail

SCRIPT="/usr/bin/update-m1n1"

OLD_LINE='gzip -c "$U_BOOT" >>"${TARGET}.new"'
NEW_LINE='gzip -nc "$U_BOOT" >>"${TARGET}.new"'

if [[ ! -r "$SCRIPT" ]]; then
    echo "ERROR: $SCRIPT is missing; cannot patch update-m1n1." >&2
    exit 1
fi

count="$(grep -Fxc -- "$OLD_LINE" "$SCRIPT" || true)"
if [[ "$count" -ne 1 ]]; then
    echo "ERROR: expected exactly one occurrence of the update-m1n1 gzip line," >&2
    echo "       found $count. Refusing to patch (fail closed)." >&2
    echo "       Expected: $OLD_LINE" >&2
    exit 1
fi

# Sanity: the fixed form must not already be present (otherwise the script file
# changed out from under us, or we would be double-patching).
if grep -Fxq -- "$NEW_LINE" "$SCRIPT"; then
    echo "ERROR: $SCRIPT already contains the patched gzip line; aborting." >&2
    exit 1
fi

# Line-based replacement (avoids regex-escaping pitfalls of sed with $, pipe,
# quotes). Preserves every other byte of the script.
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
replaced=0
while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == "$OLD_LINE" ]]; then
        printf '%s\n' "$NEW_LINE"
        replaced=1
    else
        printf '%s\n' "$line"
    fi
done < "$SCRIPT" > "$tmp"

if [[ "$replaced" -ne 1 ]]; then
    echo "ERROR: no line was replaced; refusing to overwrite." >&2
    exit 1
fi

# Verify the patched temp file before installing it.
if ! grep -Fxq -- "$NEW_LINE" "$tmp"; then
    echo "ERROR: patched gzip line missing after rewrite." >&2
    exit 1
fi
remaining="$(grep -Fxc -- "$OLD_LINE" "$tmp" || true)"
if [[ "$remaining" -ne 0 ]]; then
    echo "ERROR: after patching, the original gzip line is still present ($remaining)." >&2
    exit 1
fi

# Preserve executable bit (or default to world-executable for a /usr/bin tool).
chmod --reference="$SCRIPT" "$tmp" 2>/dev/null || chmod 755 "$tmp"
mv -f "$tmp" "$SCRIPT"
trap - EXIT

echo "Patched $SCRIPT: '$OLD_LINE' -> '$NEW_LINE'"
