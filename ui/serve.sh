#!/bin/bash
# Serve from workspace root (where config.yaml lives) so all paths resolve correctly.
# Walks up from this script's location to find config.yaml.

DIR="$(cd "$(dirname "$0")" && pwd)"
WS="$DIR"
while [[ "$WS" != "/" ]]; do
    if [[ -f "$WS/config.yaml" ]]; then
        break
    fi
    WS="$(dirname "$WS")"
done

if [[ ! -f "$WS/config.yaml" ]]; then
    echo "ERROR: Cannot find workspace root (config.yaml)." >&2
    exit 1
fi

# Compute the UI path relative to workspace root
UI_PATH="${DIR#$WS/}"
echo "Serving from: $WS"
echo "Open http://localhost:8042/$UI_PATH/"
cd "$WS" && python3 -m http.server 8042
