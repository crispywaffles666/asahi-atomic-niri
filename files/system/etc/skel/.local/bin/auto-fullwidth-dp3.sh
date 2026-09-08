#!/bin/bash
# Resize moved columns according to physical-monitor serials, not DP names.
set -uo pipefail

declare -A window_outputs=()
WIDTH_CONFIG=${NIRI_OUTPUT_WIDTHS:-${XDG_CONFIG_HOME:-$HOME/.config}/niri/output-widths.json}

parse_events() {
    jq --unbuffered -r '
      if .WindowOpenedOrChanged then
        .WindowOpenedOrChanged.window |
        select(.id != null and .workspace_id != null) |
        ["window", .id, .workspace_id, .is_focused, .is_floating] | @tsv
      elif .WindowClosed then ["closed", .WindowClosed.id] | @tsv
      else empty end'
}

handle_event() {
    local event=$1 id=$2 workspace=${3:-} focused=${4:-} floating=${5:-}
    local output previous serial width
    [[ $id =~ ^[0-9]+$ ]] || return 0
    if [[ $event == closed ]]; then
        unset 'window_outputs[$id]'
        return 0
    fi
    [[ $event == window && $focused == true && $floating == false ]] || return 0
    output=$(niri msg --json workspaces | jq -r --argjson id "$workspace" \
        '.[] | select(.id == $id) | .output // empty') || return 0
    [[ -n $output ]] || return 0
    previous=${window_outputs[$id]:-}
    window_outputs[$id]=$output
    [[ -n $previous && $previous != "$output" ]] || return 0
    serial=$(niri msg --json outputs | jq -r --arg output "$output" \
        '.[$output].serial // empty') || return 0
    width=$(jq -r --arg serial "$serial" '.[$serial] // empty' "$WIDTH_CONFIG") || return 0
    [[ $width =~ ^[0-9]+%$ ]] || return 0

    # The action targets the focused column. Do not resize a different window
    # if focus changed while we queried the workspace/output information.
    niri msg --json focused-window | jq -e --argjson id "$id" \
        '.id == $id and .is_floating == false' >/dev/null || return 0
    niri msg action set-column-width "$width"
}

main() {
    jq -e 'type == "object" and all(.[]; type == "string" and test("^[0-9]+%$"))' \
        "$WIDTH_CONFIG" >/dev/null || return 1
    while true; do
        # A reconnect starts a fresh observation history.
        window_outputs=()
        while IFS=$'\t' read -r event id workspace focused floating; do
            handle_event "$event" "$id" "$workspace" "$focused" "$floating"
        done < <(niri msg --json event-stream | parse_events)
        sleep 1
    done
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    main "$@"
fi
