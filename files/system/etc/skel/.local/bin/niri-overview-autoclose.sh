#!/bin/sh
# Close the niri overview when a new window opens.

known_ids=$(niri msg windows 2>/dev/null | grep -oP 'id: \K[0-9]+' | tr '\n' ' ')

niri msg event-stream | while read -r line; do
    case "$line" in
        "Window opened or changed:"*)
            id=$(echo "$line" | grep -oP 'id: \K[0-9]+' | head -1)
            case " $known_ids " in
                *" $id "*)  ;;
                *)
                    known_ids="$known_ids $id "
                    niri msg action close-overview 2>/dev/null
                    ;;
            esac
            ;;
        "Window closed:"*)
            id=$(echo "$line" | grep -oP 'id: \K[0-9]+' | head -1)
            known_ids=$(echo "$known_ids" | sed "s/ $id / /g")
            ;;
    esac
done
