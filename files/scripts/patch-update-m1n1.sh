#!/usr/bin/bash
# OSTree sets /usr file times to zero, which breaks `gzip -c` in update-m1n1.
# Add `-n` to drop that time. Also make the booted tree win over stale DTBS
# settings in /etc. Stop if the stock script's known lines or order change.
# See https://github.com/AsahiLinux/asahi-scripts/issues/71.
set -euo pipefail

SCRIPT="/usr/bin/update-m1n1"

OLD_GZIP='gzip -c "$U_BOOT" >>"${TARGET}.new"'
NEW_GZIP='gzip -nc "$U_BOOT" >>"${TARGET}.new"'

# Insert the new setting before the first use of DTBS.
DTBS_CHECK_LINE='if [ -z "$DTBS" ]; then'

OVERRIDE_LINE='if [ -n "${ASAHI_ATOMIC_DTBS:-}" ]; then'
OVERRIDE_BODY='    DTBS="$ASAHI_ATOMIC_DTBS"'
OVERRIDE_END='fi'

OVERRIDE_BLOCK="$(printf '%s\n'                                      \
    "$OVERRIDE_LINE"                                                \
    "$OVERRIDE_BODY"                                                \
    "$OVERRIDE_END"                                                 \
)"

if [[ ! -r "$SCRIPT" ]]; then
    echo "ERROR: $SCRIPT is missing; cannot patch update-m1n1." >&2
    exit 1
fi

count="$(grep -Fxc -- "$OLD_GZIP" "$SCRIPT" || true)"
if [[ "$count" -ne 1 ]]; then
    echo "ERROR: expected exactly one occurrence of the update-m1n1 gzip line," >&2
    echo "       found $count. Refusing to patch (fail closed)." >&2
    echo "       Expected: $OLD_GZIP" >&2
    exit 1
fi

dtbs_count="$(grep -Fxc -- "$DTBS_CHECK_LINE" "$SCRIPT" || true)"
if [[ "$dtbs_count" -ne 1 ]]; then
    echo "ERROR: expected exactly one '${DTBS_CHECK_LINE}' anchor," >&2
    echo "       found $dtbs_count. Refusing to patch (fail closed)." >&2
    exit 1
fi

# A match means this ran twice or upstream now uses the same hook.
if grep -Fq -- "$OVERRIDE_LINE" "$SCRIPT"; then
    echo "ERROR: $SCRIPT already contains the $OVERRIDE_LINE override; aborting." >&2
    exit 1
fi

if grep -Fxq -- "$NEW_GZIP" "$SCRIPT"; then
    echo "ERROR: $SCRIPT already contains the patched gzip line; aborting." >&2
    exit 1
fi

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

gzip_done=0
override_done=0

while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$gzip_done" -eq 0 && "$line" == "$OLD_GZIP" ]]; then
        printf '%s\n' "$NEW_GZIP"
        gzip_done=1
        continue
    fi
    if [[ "$override_done" -eq 0 && "$line" == "$DTBS_CHECK_LINE" ]]; then
        printf '%s\n' "$OVERRIDE_BLOCK"
        override_done=1
    fi
    printf '%s\n' "$line"
done < "$SCRIPT" > "$tmp"

if [[ "$gzip_done" -ne 1 ]]; then
    echo "ERROR: no gzip line was replaced; refusing to overwrite." >&2
    exit 1
fi
if [[ "$override_done" -ne 1 ]]; then
    echo "ERROR: the DTBS override was not inserted; refusing to overwrite." >&2
    exit 1
fi

if ! grep -Fxq -- "$NEW_GZIP" "$tmp"; then
    echo "ERROR: patched gzip line missing after rewrite." >&2
    exit 1
fi
if [[ "$(grep -Fxc -- "$OLD_GZIP" "$tmp" || true)" -ne 0 ]]; then
    echo "ERROR: after patching, the original gzip line is still present." >&2
    exit 1
fi

override_count="$(grep -Fxc -- "$OVERRIDE_LINE" "$tmp" || true)"
if [[ "$override_count" -ne 1 ]]; then
    echo "ERROR: expected exactly one $OVERRIDE_LINE in the rewritten script," >&2
    echo "       found $override_count." >&2
    exit 1
fi
if ! grep -Fxq -- "$OVERRIDE_BODY" "$tmp"; then
    echo "ERROR: override assignment line missing after rewrite." >&2
    exit 1
fi
if [[ "$(grep -Fxc -- "$OVERRIDE_END" "$tmp" || true)" -lt 1 ]]; then
    echo "ERROR: override closing 'fi' missing after rewrite." >&2
    exit 1
fi

# /etc must load first, then our setting, then the first DTBS check.
override_line="$(grep -nF -- "$OVERRIDE_LINE" "$tmp" | cut -d: -f1)"
check_line="$(grep -nF -- "$DTBS_CHECK_LINE" "$tmp" | cut -d: -f1)"
if [[ -z "$override_line" || -z "$check_line" || "$override_line" -ge "$check_line" ]]; then
    echo "ERROR: cannot prove the DTBS override precedes the DTBS empty check" >&2
    echo "       (override line $override_line, check line $check_line)." >&2
    exit 1
fi

CONFIG_LINE='[ -e /etc/sysconfig/update-m1n1 ] && . /etc/sysconfig/update-m1n1'
config_line="$(grep -nF -- "$CONFIG_LINE" "$tmp" | cut -d: -f1)"
if [[ -z "$config_line" ]]; then
    echo "ERROR: cannot locate the update-m1n1 config source line; ordering unprovable." >&2
    exit 1
fi
if [[ "$config_line" -ge "$override_line" ]]; then
    echo "ERROR: the DTBS override must appear after config sourcing, but does not." >&2
    exit 1
fi

chmod --reference="$SCRIPT" "$tmp" 2>/dev/null || chmod 755 "$tmp"
mv -f "$tmp" "$SCRIPT"
trap - EXIT

echo "Patched $SCRIPT:"
echo "  gzip: '$OLD_GZIP' -> '$NEW_GZIP'"
echo "  override: inserted '$OVERRIDE_LINE' (after config sourcing, before DTBS validation)"
