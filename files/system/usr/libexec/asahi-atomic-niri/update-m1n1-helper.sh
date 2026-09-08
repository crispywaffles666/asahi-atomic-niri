#!/usr/bin/bash
# Refresh the shared ESP when its last successfully written payload differs
# from the booted tree. Historical deployment markers cannot describe an ESP.
set -euo pipefail

MARKER_ROOT=${MARKER_ROOT:-/var/lib/asahi-atomic-niri}
MODULE_ROOT=${MODULE_ROOT:-/usr/lib/modules}
UPDATE_M1N1=${UPDATE_M1N1:-/usr/bin/update-m1n1}

log() { echo "asahi-atomic-niri-update-m1n1: $*" >&2; }
fail() { log "ERROR: $*"; exit 1; }

deployment_id() {
    # The ostree= kernel argument contains a boot checksum shared by trees.
    # Ask bootc for the actual booted OSTree commit instead. This path must
    # match the installed bootc's status schema, which has moved between
    # versions; verify after bootc upgrades on-device:
    #   bootc status --json | jq -r .status.booted.ostree.checksum
    # A schema change fails closed here (service error in the journal, no
    # marker and no ESP write), so check the unit after OS updates.
    bootc status --json | jq -er '
        .status.booted.ostree.checksum |
        select(type == "string" and test("^[a-f0-9]{64}$"))
    ' || fail "unable to determine the booted OSTree deployment"
}

find_dtbs() {
    local kver path
    kver=$(uname -r)
    [[ -n "$kver" ]] || fail "uname -r returned an empty kernel release"
    for path in "$MODULE_ROOT/$kver/dtb" "$MODULE_ROOT/$kver/dtbs"; do
        if [[ -d "$path" ]] && compgen -G "$path/apple/t6*.dtb" >/dev/null; then
            printf '%s\n' "$path"
            return
        fi
        if [[ -d "$path" ]] && compgen -G "$path/apple/t81*.dtb" >/dev/null; then
            printf '%s\n' "$path"
            return
        fi
    done
    fail "cannot find DTBs for booted kernel '$kver' under $MODULE_ROOT"
}

resolve_inputs() {
    local dtb=$1 input_file
    [[ -x "$UPDATE_M1N1" ]] || fail "'$UPDATE_M1N1' is not executable"
    input_file=$(mktemp)
    # The patched updater reports its effective paths after loading Fedora's
    # /etc configuration and defaults, but before any /run or ESP writes.
    if ! ASAHI_ATOMIC_DTBS="$dtb" ASAHI_ATOMIC_INSPECT=1 \
        "$UPDATE_M1N1" >"$input_file"; then
        rm -f "$input_file"
        fail "cannot inspect update-m1n1 inputs"
    fi
    mapfile -d '' -t payload_inputs <"$input_file"
    rm -f "$input_file"
    [[ ${#payload_inputs[@]} -eq 5 ]] \
        || fail "updater disabled or missing the Atomic inspection hook; no success recorded"
    [[ -s ${payload_inputs[0]} && -s ${payload_inputs[1]} ]] \
        || fail "m1n1 or U-Boot input is missing/empty"
    [[ ${payload_inputs[3]} == "$dtb" ]] || fail "updater resolved another tree's DTBs"
}

payload_hash() (
    local dtb=$1 file
    export LC_ALL=C
    shopt -s nullglob
    local dtbs=("$dtb"/apple/t6*.dtb "$dtb"/apple/t81*.dtb)
    ((${#dtbs[@]})) || fail "no Apple DTBs in $dtb"
    {
        printf 'asahi-atomic-payload-v1\n'
        # Include updater changes as well as every binary/config input.
        for file in "$UPDATE_M1N1" "${payload_inputs[0]}" "${payload_inputs[1]}"; do
            sha256sum <"$file" || exit 1
        done
        for file in "${dtbs[@]}"; do
            printf '%s\n' "${file##*/}"
            sha256sum <"$file" || exit 1
        done
        if [[ -f ${payload_inputs[2]} ]]; then
            sha256sum <"${payload_inputs[2]}" || exit 1
        else
            printf 'no-m1n1-config\n'
        fi
        printf 'target=%s\n' "${payload_inputs[4]}"
    } | sha256sum | cut -d ' ' -f1
)

is_current() {
    [[ -r "$MARKER_ROOT/current-payload" ]] \
        && [[ $(<"$MARKER_ROOT/current-payload") == "$1" ]]
}

record_current() (
    local marker_tmp
    marker_tmp=$(mktemp "$MARKER_ROOT/.current-payload.XXXXXX")
    trap 'rm -f "$marker_tmp"' EXIT
    printf '%s\n' "$1" >"$marker_tmp"
    sync -f "$marker_tmp"
    mv -f "$marker_tmp" "$MARKER_ROOT/current-payload"
    sync -f "$MARKER_ROOT"
)

check_gzip() (
    local uboot=${ASAHI_UBOOT:-} tmp
    if [[ -z "$uboot" ]]; then
        for uboot in /usr/share/uboot/apple_m1/u-boot-nodtb.bin /usr/lib/asahi-boot/u-boot-nodtb.bin; do
            [[ -s "$uboot" ]] && break
        done
    fi
    [[ -s "$uboot" ]] || fail "cannot locate the Asahi U-Boot binary"
    tmp=$(mktemp)
    trap 'rm -f "$tmp"' EXIT
    if ! gzip -nc "$uboot" >"$tmp" || ! gzip -t "$tmp"; then
        fail "gzip -nc failed for '$uboot'"
    fi
    log "gzip -nc validated (no ESP write)"
)

check() {
    local dtb id fingerprint
    dtb=$(find_dtbs)
    id=$(deployment_id)
    resolve_inputs "$dtb"
    fingerprint=$(payload_hash "$dtb")
    ASAHI_UBOOT=${payload_inputs[1]} check_gzip
    log "booted deployment: $id; DTBs: $dtb; payload: $fingerprint"
    if is_current "$fingerprint"; then
        log "payload matches the last successful ESP refresh"
    else
        log "payload needs an ESP refresh"
    fi
}

refresh() (
    local dtb id fingerprint
    mkdir -p "$MARKER_ROOT"
    exec 9>"$MARKER_ROOT/refresh.lock"
    flock -x 9
    dtb=$(find_dtbs)
    id=$(deployment_id)
    resolve_inputs "$dtb"
    fingerprint=$(payload_hash "$dtb")
    if is_current "$fingerprint"; then
        log "payload $fingerprint already current (deployment $id); skipping"
        return
    fi
    ASAHI_UBOOT=${payload_inputs[1]} check_gzip

    # Failed updates may partially touch the ESP. Invalidate the old claim
    # before writing, so returning to the old tree also retries after failure.
    rm -f "$MARKER_ROOT/current-payload"
    sync -f "$MARKER_ROOT"
    unset DTBS ASAHI_ATOMIC_INSPECT
    export ASAHI_ATOMIC_DTBS="$dtb"
    log "refreshing payload $fingerprint for deployment $id"
    "$UPDATE_M1N1" || fail "update-m1n1 failed; no current payload recorded"

    # The default updater unmounts/flushes its ESP. An explicit custom TARGET
    # stays mounted, so flush that filesystem before making the marker durable.
    if [[ -n ${payload_inputs[4]} ]]; then
        sync -f "${payload_inputs[4]}"
    fi

    resolve_inputs "$dtb"
    [[ $(payload_hash "$dtb") == "$fingerprint" ]] \
        || fail "payload inputs changed during update; no current payload recorded"
    record_current "$fingerprint"
    log "refresh complete; reboot to use the new stage-2 payload"
)

main() {
    case "${1:-}" in
        deployment-id) deployment_id ;;
        resolve-dtb) find_dtbs ;;
        gzip-check) check_gzip ;;
        check) check ;;
        refresh) refresh ;;
        *) echo "usage: $0 {deployment-id|resolve-dtb|gzip-check|check|refresh}" >&2; return 2 ;;
    esac
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    main "$@"
fi
