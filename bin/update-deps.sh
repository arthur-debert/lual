#!/usr/bin/env bash
set -e
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
cd "$SCRIPT_DIR/.."

# Find all rockspecs
MAIN_ROCKSPEC=$(find . -maxdepth 1 -name "lual-*.rockspec" | grep -v "lualextras" | head -1)
EXTRAS_ROCKSPEC=$(find . -maxdepth 1 -name "lualextras-*.rockspec" | head -1)

if [ -z "$MAIN_ROCKSPEC" ]; then
    echo "Error: No lual-*.rockspec file found"
    exit 1
fi

echo "Purging luarocks cache"
# Only purge if .luarocks directory exists and has content
if [ -d "./.luarocks" ] && [ "$(ls -A ./.luarocks 2>/dev/null)" ]; then
    luarocks --tree ./.luarocks purge
fi

echo "Installing dependencies from $MAIN_ROCKSPEC"
luarocks --tree ./.luarocks install --only-deps "$MAIN_ROCKSPEC"

if [ -n "$EXTRAS_ROCKSPEC" ]; then
    echo "Installing dependencies from $EXTRAS_ROCKSPEC"
    luarocks --tree ./.luarocks install --only-deps "$EXTRAS_ROCKSPEC"
fi

echo "Done"
