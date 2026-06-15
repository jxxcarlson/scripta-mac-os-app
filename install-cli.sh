#!/bin/sh
# Install the `scripta` CLI to /opt/homebrew/bin.
set -e
SRC="$(cd "$(dirname "$0")" && pwd)/bin/scripta"
DEST="/opt/homebrew/bin/scripta"
cp "$SRC" "$DEST"
chmod +x "$DEST"
echo "Installed scripta -> $DEST"
