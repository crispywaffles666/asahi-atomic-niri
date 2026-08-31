#!/bin/bash
DIR="$HOME/Pictures/Screenshots"
mkdir -p "$DIR"

while read -r file <&3; do
    case "$file" in *.png) ;; *) continue ;; esac
    path="$DIR/$file"
    (
        action=$(notify-send -a "Screenshot" "Screenshot saved: $file" "" \
            -i "$path" \
            --action="annotate=Annotate" \
            --action="open=Open" \
            --action="copy=Copy")
        case "$action" in
            annotate) satty -f "$path" ;;
            open)     xdg-open "$path" ;;
            copy)     wl-copy < "$path" ;;
        esac
    ) &
done 3< <(inotifywait -m -e close_write --format '%f' "$DIR")
