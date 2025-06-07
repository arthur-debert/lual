#!/usr/bin/env bash
set -e
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
cd "$SCRIPT_DIR/../.."
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
    echo "Purging luarocks cache"
    luarocks --tree ./.luarocks purge
fi

echo "Installing dependencies from $MAIN_ROCKSPEC"
luarocks --tree ./.luarocks install --only-deps "$MAIN_ROCKSPEC"

if [ -n "$EXTRAS_ROCKSPEC" ]; then
    echo "Installing dependencies from $EXTRAS_ROCKSPEC"
    luarocks --tree ./.luarocks install --only-deps "$EXTRAS_ROCKSPEC"
fi

# Install extra dependencies from extra-deps directory
EXTRA_DEPS_DIR="./extra-deps"
if [ -d "$EXTRA_DEPS_DIR" ]; then
    echo "Installing extra dependencies from $EXTRA_DEPS_DIR"
    for dep_file in "$EXTRA_DEPS_DIR"/*; do
        if [ -f "$dep_file" ]; then
            dep_line=$(cat "$dep_file" | tr -d '\n\r' | xargs)
            if [ -n "$dep_line" ]; then
                # Extract just the package name (before any version constraint)
                dep_name=$(echo "$dep_line" | awk '{print $1}')
                echo "Installing extra dependency: $dep_name (from: $dep_line)"
                luarocks --tree ./.luarocks install "$dep_name"
            fi
        fi
    done
fi

echo "Deps installed, running tests"
busted
