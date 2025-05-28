#!/usr/bin/env bash
set -e
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
cd "$SCRIPT_DIR/.."

# Find the current rockspec
ROCKSPEC=$(find . -maxdepth 1 -name "lual-*.rockspec" | head -1)
if [ -z "$ROCKSPEC" ]; then
    echo "Error: No lual-*.rockspec file found"
    exit 1
fi

echo "Purging luarocks cache"
luarocks --tree ./.luarocks purge
echo "Installing dependencies from $ROCKSPEC"
luarocks --tree ./.luarocks install --only-deps "$ROCKSPEC"
echo "Done"
