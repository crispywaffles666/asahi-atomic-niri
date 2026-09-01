#!/usr/bin/bash
# Fail-closed build-time patch for the Asahi `update-m1n1` script on Atomic.
#
# Two, independently-verified hardening changes are applied to the stock
# `/usr/bin/update-m1n1`:
#
#  A) gzip timestamp fix. OSTree canonicalizes package-owned files under /usr to
#     an epoch-zero mtime. `gzip -c` refuses to encode that (uint32 gzip
#     timestamp range) and, under `set -e`, aborts with status 2, breaking the
#     m1n1/U-Boot refresh. Passing `-n` omits the volatile filename+timestamp
#     header (the decompressed payload is byte-identical) and avoids the abort.
#     https://github.com/AsahiLinux/asahi-scripts/issues/71
#
#  B) Namespaced DTB override. Fedora's `update-m1n1` sources its own config
#     (/etc/default/update-m1n1) near startup; that config is allowed to set
#     `DTBS` unconditionally and would otherwise silently clobber the
#     deployment-aware DTB directory exported by this image's helper. To make
#     the handoff explicit and provable, we inject a namespaced override that is
#     applied *after* the normal config/functions are sourced and *before* the
#     `DTBS` value is validated or used, so that a persistent /etc config can
#     never silently replace the booted deployment's device trees.
#
# This script is intentionally strict ("fail closed"): it refuses to build if any
# expected source anchor is missing or duplicated, if a change was already
# applied, or if the resulting ordering cannot be proven. It does not silently
# adapt to unknown upstream changes.
set -euo pipefail

SCRIPT="/usr/bin/update-m1n1"

# --- Identities -------------------------------------------------------------

OLD_GZIP='gzip -c "$U_BOOT" >>"${TARGET}.new"'
NEW_GZIP='gzip -nc "$U_BOOT" >>"${TARGET}.new"'

# Anchor that terminates the "config + functions sourced" preamble and opens the
# section where DTBS is validated/used. The override block is inserted directly
# before this exact line, guaranteeing it runs after config sourcing and before
# the DTBS empty check / glob expansion.
DTBS_CHECK_LINE='if [ -z "$DTBS" ]; then'

OVERRIDE_LINE='if [ -n "${ASAHI_ATOMIC_DTBS:-}" ]; then'
OVERRIDE_BODY='    DTBS="$ASAHI_ATOMIC_DTBS"'
OVERRIDE_END='fi'

# The full override block inserted, as it must appear in the final script.
OVERRIDE_BLOCK="$(printf '%s\n'                                      \
    "$OVERRIDE_LINE"                                                \
    "$OVERRIDE_BODY"                                                \
    "$OVERRIDE_END"                                                 \
)"

if [[ ! -r "$SCRIPT" ]]; then
    echo "ERROR: $SCRIPT is missing; cannot patch update-m1n1." >&2
    exit 1
fi

# --- Phase 1: verify the source script matches known upstream structure -----

count="$(grep -Fxc -- "$OLD_GZIP" "$SCRIPT" || true)"
if [[ "$count" -ne 1 ]]; then
    echo "ERROR: expected exactly one occurrence of the update-m1n1 gzip line," >&2
    echo "       found $count. Refusing to patch (fail closed)." >&2
    echo "       Expected: $OLD_GZIP" >&2
    exit 1
fi

# The DTBS empty-check anchor must be present exactly once.
dtbs_count="$(grep -Fxc -- "$DTBS_CHECK_LINE" "$SCRIPT" || true)"
if [[ "$dtbs_count" -ne 1 ]]; then
    echo "ERROR: expected exactly one '${DTBS_CHECK_LINE}' anchor," >&2
    echo "       found $dtbs_count. Refusing to patch (fail closed)." >&2
    exit 1
fi

# The override must not already be present (would imply double-patching or an
# unknown upstream change that happens to reuse our namespaced hook).
if grep -Fq -- "$OVERRIDE_LINE" "$SCRIPT"; then
    echo "ERROR: $SCRIPT already contains the $OVERRIDE_LINE override; aborting." >&2
    exit 1
fi

# Sanity: the fixed gzip form must not already be present.
if grep -Fxq -- "$NEW_GZIP" "$SCRIPT"; then
    echo "ERROR: $SCRIPT already contains the patched gzip line; aborting." >&2
    exit 1
fi

# --- Phase 2: rewrite, applying both changes to a temp copy -----------------
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

done_gzip=0
done_override=0

while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$done_gzip" -eq 0 && "$line" == "$OLD_GZIP" ]]; then
        printf '%s\n' "$NEW_GZIP"
        done_gzip=1
        continue
    fi
    if [[ "$done_override" -eq 0 && "$line" == "$DTBS_CHECK_LINE" ]]; then
        # Prepend the override block immediately before the DTBS empty check.
        printf '%s\n' "$OVERRIDE_BLOCK"
        done_override=1
    fi
    printf '%s\n' "$line"
done < "$SCRIPT" > "$tmp"

# --- Phase 3: verify the rewritten temp file --------------------------------

if [[ "$done_gzip" -ne 1 ]]; then
    echo "ERROR: no gzip line was replaced; refusing to overwrite." >&2
    exit 1
fi
if [[ "$done_override" -ne 1 ]]; then
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

# Exactly one override block must be present in the final result.
ov_count="$(grep -Fxc -- "$OVERRIDE_LINE" "$tmp" || true)"
if [[ "$ov_count" -ne 1 ]]; then
    echo "ERROR: expected exactly one $OVERRIDE_LINE in the rewritten script," >&2
    echo "       found $ov_count." >&2
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

# --- Phase 4: prove ordering of override vs DTBS validation -----------------

# The override must appear before the DTBS empty check in the final script.
override_pos="$(grep -nF -- "$OVERRIDE_LINE" "$tmp" | cut -d: -f1)"
check_pos="$(grep -nF -- "$DTBS_CHECK_LINE" "$tmp" | cut -d: -f1)"
if [[ -z "$override_pos" || -z "$check_pos" || "$override_pos" -ge "$check_pos" ]]; then
    echo "ERROR: cannot prove the DTBS override precedes the DTBS empty check" >&2
    echo "       (override line $override_pos, check line $check_pos)." >&2
    exit 1
fi

# The override must also appear after the config default is sourced.
# The config default source line must be present exactly once.
CONFIG_LINE='[ -e /etc/default/update-m1n1 ] && . /etc/default/update-m1n1'
config_pos="$(grep -nF -- "$CONFIG_LINE" "$tmp" | cut -d: -f1)"
if [[ -z "$config_pos" ]]; then
    echo "ERROR: cannot locate the update-m1n1 config source line; ordering unprovable." >&2
    exit 1
fi
if [[ "$config_pos" -ge "$override_pos" ]]; then
    echo "ERROR: the DTBS override must appear after config sourcing, but does not." >&2
    exit 1
fi

# --- Phase 5: install --------------------------------------------------------
chmod --reference="$SCRIPT" "$tmp" 2>/dev/null || chmod 755 "$tmp"
mv -f "$tmp" "$SCRIPT"
trap - EXIT

echo "Patched $SCRIPT:"
echo "  gzip: '$OLD_GZIP' -> '$NEW_GZIP'"
echo "  override: inserted '$OVERRIDE_LINE' (after config sourcing, before DTBS validation)"
