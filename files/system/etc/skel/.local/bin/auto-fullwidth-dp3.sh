#!/bin/bash

declare -A window_outputs

get_output_for_workspace() {
    niri msg --json workspaces | jq -r --argjson workspace_id "$1" \
        '.[] | select(.id == $workspace_id) | .output // empty'
}

get_serial_for_output() {
    niri msg --json outputs | jq -r --arg output "$1" \
        '.[$output].serial // empty'
}

while true; do
    while read -r line; do
        if echo "$line" | grep -q '"WindowOpenedOrChanged"'; then
            window_id=$(echo "$line" | grep -o '"id":[0-9]*' | head -1 | grep -o '[0-9]*')
            window_ws=$(echo "$line" | grep -o '"workspace_id":[0-9]*' | head -1 | grep -o '[0-9]*')
            is_focused=$(echo "$line" | grep -o '"is_focused":true')
            is_floating=$(echo "$line" | grep -o '"is_floating":true')

            if [ -n "$window_ws" ] && [ -n "$is_focused" ] && [ -n "$window_id" ] && [ -z "$is_floating" ]; then
                output=$(get_output_for_workspace "$window_ws")
                last_output="${window_outputs[$window_id]}"
                window_outputs[$window_id]="$output"

                # Skip if no previous output (new window) or monitor hasn't changed
                [ -z "$last_output" ] || [ "$last_output" = "$output" ] && continue

                # Connector names can change after resume (for example DP-4 to
                # DP-5), so identify the physical monitor by its EDID serial.
                monitor_serial=$(get_serial_for_output "$output")
                [ -z "$monitor_serial" ] && continue

                sleep 0.1
                if [ "$monitor_serial" = "CN41254B6B" ]; then
                    niri msg action set-column-width "100%"
                elif [ "$monitor_serial" = "CN41170Z70" ]; then
                    niri msg action set-column-width "50%"
                    sleep 0.02
                    niri msg action focus-column-left
                    sleep 0.02
                    niri msg action focus-column-right
                fi
            fi
        fi

        if echo "$line" | grep -q '"WindowClosed"'; then
            closed_id=$(echo "$line" | grep -o '[0-9]*$')
            unset window_outputs[$closed_id] 2>/dev/null
        fi
    done < <(niri msg --json event-stream)
    sleep 1
done
