#!/usr/bin/env bash
set -e
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
cd "$SCRIPT_DIR/.."
echo "Purging luarocks cache"
luarocks --tree ./.luarocks purge
echo "Installing dependencies"
luarocks --tree ./.luarocks install --only-deps lual-0.1.0-1.rockspec
echo "Done"
