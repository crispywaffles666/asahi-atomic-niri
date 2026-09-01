#!/usr/bin/bash
# asahi-atomic-niri m1n1 / U-Boot / device-tree refresh helper.
#
# Fedora Asahi Atomic (OSTree/bootc) cannot refresh the Asahi stage-2
# m1n1 payload (ESP:/m1n1/boot.bin) at package/image-build time, and must not
# use the stale legacy /boot/dtb symlink (which is a Fedora ARM postinst
# artifact; `grubby` is excluded from this base image). Instead, the device
# trees are taken from the *currently booted* deployment's own /usr tree, keyed
# off the kernel release reported by `uname -r`. Because this helper only runs
# after a new deployment has booted successfully, resolving the DTB dir through
# /usr/lib/modules/$(uname -r) is inherently deployment-aware and can never
# pick an arbitrary/lexicographically-newest directory.
#
# Where the DTB path comes from (documented derivation):
#   kver    := $(uname -r)                       # kernel release of booted deployment
#   DTBDIR  := /usr/lib/modules/$kver/dtb        # canonical dir, populated by the
#                                                 #   dracut-asahi kernel-install hook
#                                                 #   (/usr/lib/kernel/install.d/15-...)
#   DTBS    := ${DTBDIR}/apple/t6*.dtb ${DTBDIR}/apple/t81*.dtb   # all Apple M-series DTBs
#
# update-m1n1 is invoked with DTBS exported so it embeds the booted deployment's
# DTBs (plus m1n1 + gzipped U-Boot) into boot.bin.
#
# Subcommands:
#   deployment-id  Print the stable booted-deployment identifier (fail closed).
#   resolve-dtb    Print the resolved deployment DTB directory (fail closed).
#   gzip-check     Non-destructive: prove `gzip -nc` works vs the installed
#                  U-Boot without writing the ESP (safe at build time too).
#   check          Non-destructive deployment check (gzip + DTB + status).
#   refresh        Deployment-aware refresh: run update-m1n1, then record success.
set -euo pipefail

# Overridable via env for non-root verification/testing.
MARKER_ROOT=${MARKER_ROOT:-/var/lib/asahi-atomic-niri}
MODULE_ROOT=${MODULE_ROOT:-/usr/lib/modules}
UPDATE_M1N1=${UPDATE_M1N1:-/usr/bin/update-m1n1}

log() { echo "asahi-atomic-niri-update-m1n1: $*" >&2; }

failclosed() {
    echo "ERROR: $*" >&2
    exit 1
}

# Stable deployment identifier: the OSTree commit checksum of the booted
# deployment, taken from the ostree= kernel karg (how OSTree/bootc itself
# identifies the booted deployment) and normalized to just the commit checksum
# so it is stable regardless of which /ostree/boot.N/ array the deployment is
# currently served from. Falls back to `bootc status --json` if the karg is
# missing. We deliberately do NOT use `uname -r` alone, because two deployments
# can share a kernel release.
deployment_id() {
    local id="" karg=""
    karg="$(tr ' ' '\n' </proc/cmdline | sed -n 's/^ostree=//p')"
    if [[ -n "$karg" ]]; then
        # karg == /ostree/boot.N/<stateroot>/<checksum>[/serial]
        karg="${karg#/ostree/boot.}"
        karg="${karg#*/}"        # now: <stateroot>/<checksum>[/serial]
        id="$(printf '%s' "$karg" | cut -d/ -f2)"   # the commit checksum
        if [[ -n "$id" ]]; then
            printf '%s\n' "$id"
            return 0
        fi
    fi

    if command -v bootc >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
        # bootc status JSON: 'booted' object with 'checksum'
        id="$(bootc status --json 2>/dev/null \
            | python3 -c 'import json,sys; d=json.load(sys.stdin); b=d.get("booted") or {}; print(b.get("checksum",""))' \
        )"
        if [[ -n "$id" ]]; then
            printf '%s\n' "$id"
            return 0
        fi
    fi

    failclosed "unable to determine the booted deployment identifier"
}

# Resolve the DTB directory for the currently booted deployment. Fails closed
# (never guesses) if the deployment's own DTB set cannot be found.
resolve_dtb() {
    local kver="" cand=""
    kver="$(uname -r)"
    if [[ -z "$kver" ]]; then
        failclosed "uname -r returned an empty kernel release"
    fi

    # Canonical location populated by the dracut-asahi kernel-install hook.
    cand="${MODULE_ROOT}/${kver}/dtb"
    if [[ -d "$cand" ]] && [[ -n "$(ls "$cand"/apple/t6*.dtb "$cand"/apple/t81*.dtb 2>/dev/null)" ]]; then
        printf '%s\n' "$cand"
        return 0
    fi

    # Secondary name used by some Asahi packaging (dtbs/, plural).
    cand="${MODULE_ROOT}/${kver}/dtbs"
    if [[ -d "$cand" ]] && [[ -n "$(ls "$cand"/apple/t6*.dtb "$cand"/apple/t81*.dtb 2>/dev/null)" ]]; then
        printf '%s\n' "$cand"
        return 0
    fi

    failclosed "cannot resolve a DTB directory for the booted deployment kernel '$kver' (looked under /usr/lib/modules, which is already deployment-specific)"
}

marker_for() {
    # $1 = deployment id. Marker paths are anchored under /var (shared and
    # persistent across deployments on OSTree), keyed by deployment id.
    printf '%s/updates/%s\n' "$MARKER_ROOT" "$(printf '%s' "$1" | tr '/' '_')"
}

is_done() {
    local marker
    marker="$(marker_for "$1")"
    [[ -f "$marker" ]]
}

record_done() {
    local marker
    marker="$(marker_for "$1")"
    mkdir -p "$(dirname "$marker")" || failclosed "cannot create marker dir for deployment"
    printf 'refreshed at %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >"$marker"
    log "recorded m1n1 refresh success for deployment $1"
}

# Non-destructive proof that `gzip -nc` works against the installed U-Boot
# binary without writing the ESP. Uses a temp file only.
verify_gzip_nc() {
    [[ -x "$UPDATE_M1N1" ]] || failclosed "'$UPDATE_M1N1' not found or not executable"

    local uboot=""
    # Resolve the U-Boot payload the same way update-m1n1 does. Allow override
    # (e.g. for non-root verification / testing against a copied binary).
    if [[ -n "${ASAHI_UBOOT:-}" && -f "$ASAHI_UBOOT" ]]; then
        uboot="$ASAHI_UBOOT"
    elif [[ -f /usr/share/uboot/apple_m1/u-boot-nodtb.bin ]]; then
        uboot=/usr/share/uboot/apple_m1/u-boot-nodtb.bin
    elif [[ -f /usr/lib/asahi-boot/u-boot-nodtb.bin ]]; then
        uboot=/usr/lib/asahi-boot/u-boot-nodtb.bin
    else
        failclosed "cannot locate the Asahi U-Boot binary for the gzip -nc test"
    fi

    local tmp=""
    tmp="$(mktemp)"
    # Guarded trap: `|:-` avoids `set -u` aborting on the (now unset) local.
    trap '[[ -n "${tmp:-}" ]] && rm -f "$tmp"' RETURN
    # -nc emits no filename/timestamp header; epoch-zero mtime would otherwise
    # make gzip -c abort with "file timestamp out of range for gzip format".
    if ! gzip -nc "$uboot" >"$tmp"; then
        failclosed "gzip -nc failed against '$uboot' (would also abort update-m1n1)"
    fi
    if ! gzip -t "$tmp" 2>/dev/null; then
        failclosed "gzip -nc output failed integrity check"
    fi
    log "gzip -nc validated against '$uboot' (decompresses cleanly; no ESP write)"
}

cmd_check() {
    verify_gzip_nc
    local dtb id
    dtb="$(resolve_dtb)"
    id="$(deployment_id)"
    log "resolved deployment DTB dir: $dtb"
    log "booted deployment id:         $id"
    if is_done "$id"; then
        log "this deployment has already been refreshed; nothing to do"
    else
        log "this deployment has NOT yet been refreshed"
    fi
}

# Non-destructive build/runtime-safe proof that the patched update-m1n1 gzip
# invocation is actually safe against the installed U-Boot. Writes only a temp
# file (never the ESP), so it is safe to run during the image build.
cmd_gzip_check() {
    verify_gzip_nc
}

cmd_refresh() {
    local dtb id
    dtb="$(resolve_dtb)"
    id="$(deployment_id)"

    if is_done "$id"; then
        log "deployment $id already refreshed; skipping"
        return 0
    fi

    # Sanity before touching the ESP.
    verify_gzip_nc

    [[ -x "$UPDATE_M1N1" ]] || failclosed "'$UPDATE_M1N1' not found or not executable"

    # Export DTBS (update-m1n1 reads it; it must be a directory so the script
    # expands the platform globs itself).
    export DTBS="$dtb"
    log "refreshing m1n1/U-Boot/DTBs from $dtb (deployment $id)"
    if ! "$UPDATE_M1N1"; then
        # Fail closed: do NOT mark this deployment done.
        failclosed "update-m1n1 failed for deployment $id; not marking as refreshed"
    fi

    record_done "$id"
    log "m1n1/U-Boot/DTB refresh complete; a reboot is required for the new stage-2 payload to take effect"
}

case "${1:-}" in
    deployment-id) deployment_id ;;
    resolve-dtb)   resolve_dtb ;;
    gzip-check)    cmd_gzip_check ;;
    check)         cmd_check ;;
    refresh)       cmd_refresh ;;
    *)
        echo "usage: $0 {deployment-id|resolve-dtb|gzip-check|check|refresh}" >&2
        exit 2
        ;;
esac
