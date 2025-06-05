#!/usr/bin/env bash
set -e
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
cd "$SCRIPT_DIR/.."
#    "lua >= 5.1",
#    "dkjson >= 2.5",
#    "luasocket >= 3.0rc1-2",
#    "busted >= 2.0.0",
#    "luv >= 1.51.0-1"
# Find all rockspecs
MAIN_ROCKSPEC=$(find . -maxdepth 1 -name "lual-*.rockspec" | grep -v "lualextras" | head -1)

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
