#!/usr/bin/bash
# Use the booted tree's device files, never the stale /boot/dtb link. Running
# after boot ties `uname -r` to that tree. ASAHI_ATOMIC_DTBS then wins over old
# settings in /etc without letting them pick another tree.
set -euo pipefail

# Tests can point these paths at temp files.
MARKER_ROOT=${MARKER_ROOT:-/var/lib/asahi-atomic-niri}
MODULE_ROOT=${MODULE_ROOT:-/usr/lib/modules}
UPDATE_M1N1=${UPDATE_M1N1:-/usr/bin/update-m1n1}

log() { echo "asahi-atomic-niri-update-m1n1: $*" >&2; }

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

# Use the tree hash as its ID; two trees may share a kernel release.
deployment_id() {
    local id="" karg=""
    karg="$(tr ' ' '\n' </proc/cmdline | sed -n 's/^ostree=//p')"
    if [[ -n "$karg" ]]; then
        # Path shape: /ostree/boot.N/<stateroot>/<checksum>[/serial]
        karg="${karg#/ostree/boot.}"
        karg="${karg#*/}"
        id="$(printf '%s' "$karg" | cut -d/ -f2)"
        if [[ -n "$id" ]]; then
            printf '%s\n' "$id"
            return 0
        fi
    fi

    if command -v bootc >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
        id="$(bootc status --json 2>/dev/null \
            | python3 -c 'import json,sys; d=json.load(sys.stdin); b=d.get("booted") or {}; print(b.get("checksum",""))' \
        )"
        if [[ -n "$id" ]]; then
            printf '%s\n' "$id"
            return 0
        fi
    fi

    fail "unable to determine the booted deployment identifier"
}

find_dtbs() {
    local kver="" path=""
    kver="$(uname -r)"
    if [[ -z "$kver" ]]; then
        fail "uname -r returned an empty kernel release"
    fi

    # dracut-asahi uses dtb, but some Asahi packages use dtbs.
    path="${MODULE_ROOT}/${kver}/dtb"
    if [[ -d "$path" ]] && [[ -n "$(ls "$path"/apple/t6*.dtb "$path"/apple/t81*.dtb 2>/dev/null)" ]]; then
        printf '%s\n' "$path"
        return 0
    fi

    path="${MODULE_ROOT}/${kver}/dtbs"
    if [[ -d "$path" ]] && [[ -n "$(ls "$path"/apple/t6*.dtb "$path"/apple/t81*.dtb 2>/dev/null)" ]]; then
        printf '%s\n' "$path"
        return 0
    fi

    fail "cannot find DTBs for the booted kernel '$kver' under /usr/lib/modules"
}

marker_for() {
    # /var spans OSTree trees, so key each mark by tree ID.
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
    mkdir -p "$(dirname "$marker")" || fail "cannot create marker dir for deployment"
    printf 'refreshed at %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >"$marker"
    log "recorded m1n1 refresh success for deployment $1"
}

check_gzip() {
    [[ -x "$UPDATE_M1N1" ]] || fail "'$UPDATE_M1N1' not found or not executable"

    local uboot=""
    # Tests may point this at a copied U-Boot file.
    if [[ -n "${ASAHI_UBOOT:-}" && -f "$ASAHI_UBOOT" ]]; then
        uboot="$ASAHI_UBOOT"
    elif [[ -f /usr/share/uboot/apple_m1/u-boot-nodtb.bin ]]; then
        uboot=/usr/share/uboot/apple_m1/u-boot-nodtb.bin
    elif [[ -f /usr/lib/asahi-boot/u-boot-nodtb.bin ]]; then
        uboot=/usr/lib/asahi-boot/u-boot-nodtb.bin
    else
        fail "cannot locate the Asahi U-Boot binary for the gzip -nc test"
    fi

    local tmp=""
    tmp="$(mktemp)"
    # The default keeps `set -u` from failing after this local goes out of scope.
    trap '[[ -n "${tmp:-}" ]] && rm -f "$tmp"' RETURN
    # -n drops the timestamp that OSTree sets to zero and gzip rejects.
    if ! gzip -nc "$uboot" >"$tmp"; then
        fail "gzip -nc failed against '$uboot' (would also abort update-m1n1)"
    fi
    if ! gzip -t "$tmp" 2>/dev/null; then
        fail "gzip -nc output failed integrity check"
    fi
    log "gzip -nc validated against '$uboot' (decompresses cleanly; no ESP write)"
}

check() {
    check_gzip
    local dtb id
    dtb="$(find_dtbs)"
    id="$(deployment_id)"
    log "resolved deployment DTB dir: $dtb"
    log "booted deployment id:         $id"
    if is_done "$id"; then
        log "this deployment has already been refreshed; nothing to do"
    else
        log "this deployment has NOT yet been refreshed"
    fi
}

gzip_check() {
    check_gzip
}

refresh() {
    local dtb id
    dtb="$(find_dtbs)"
    id="$(deployment_id)"

    if is_done "$id"; then
        log "deployment $id already refreshed; skipping"
        return 0
    fi

    # Stop before touching the ESP if gzip cannot read this U-Boot file.
    check_gzip

    [[ -x "$UPDATE_M1N1" ]] || fail "'$UPDATE_M1N1' not found or not executable"

    # The patched script reads this after /etc. Drop plain DTBS so /etc cannot win.
    unset DTBS || true
    export ASAHI_ATOMIC_DTBS="$dtb"
    log "refreshing m1n1/U-Boot/DTBs from $dtb (deployment $id)"
    if ! "$UPDATE_M1N1"; then
        fail "update-m1n1 failed for deployment $id; not marking as refreshed"
    fi

    record_done "$id"
    log "m1n1/U-Boot/DTB refresh complete; a reboot is required for the new stage-2 payload to take effect"
}

case "${1:-}" in
    deployment-id) deployment_id ;;
    resolve-dtb)   find_dtbs ;;
    gzip-check)    gzip_check ;;
    check)         check ;;
    refresh)       refresh ;;
    *)
        echo "usage: $0 {deployment-id|resolve-dtb|gzip-check|check|refresh}" >&2
        exit 2
        ;;
esac
