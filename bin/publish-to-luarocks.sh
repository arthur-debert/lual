#!/usr/bin/env bash
set -e

# Publishes rockspec files to LuaRocks.
# Usage: ./publish-to-luarocks.sh [--dry-run] <rockspec_file1> [rockspec_file2 ...]

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
PROJECT_ROOT="$SCRIPT_DIR/.."
cd "$PROJECT_ROOT" # Ensure we are in the project root

# Colors
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'
print_status_stderr() { echo -e "${BLUE}[INFO]${NC} $1" >&2; }
print_warning_stderr() { echo -e "${YELLOW}[WARNING]${NC} $1" >&2; }
print_error_stderr() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
    exit 1
}

DRY_RUN_ARG=""
if [ "$1" = "--dry-run" ]; then
    DRY_RUN_ARG="--dry-run"
    shift
fi

if [ "$#" -eq 0 ]; then
    print_error_stderr "Error: At least one rockspec file argument is required for publishing."
fi

for rockspec_file in "$@"; do
    if [ ! -f "$rockspec_file" ]; then
        print_error_stderr "Rockspec file not found: $rockspec_file"
    fi

    print_status_stderr "Preparing to publish ${rockspec_file} to LuaRocks..."

    if [ -z "$LUAROCKS_API_KEY" ]; then
        print_warning_stderr "LUAROCKS_API_KEY environment variable not set."
        if [ "$DRY_RUN_ARG" != "--dry-run" ]; then
            read -p "Enter your LuaRocks API key (or press Enter to skip this file): " -s API_KEY_INPUT >&2
            echo >&2
            if [ -z "$API_KEY_INPUT" ]; then
                print_warning_stderr "Skipping $rockspec_file due to no API key provided."
                continue
            fi
            TEMP_LUAROCKS_API_KEY="$API_KEY_INPUT"
        else
            print_warning_stderr "DRY RUN: Would need LUAROCKS_API_KEY."
            TEMP_LUAROCKS_API_KEY="DRY_RUN_API_KEY_PLACEHOLDER" # for dry run message
        fi
    else
        TEMP_LUAROCKS_API_KEY="$LUAROCKS_API_KEY"
    fi

    if [ "$DRY_RUN_ARG" = "--dry-run" ]; then
        print_warning_stderr "DRY RUN: Would upload: luarocks upload $rockspec_file --api-key=***"
    else
        print_status_stderr "Uploading $rockspec_file to LuaRocks..."
        if luarocks upload "$rockspec_file" --api-key="$TEMP_LUAROCKS_API_KEY"; then
            print_status_stderr "Successfully published $rockspec_file to LuaRocks!"
        else
            print_error_stderr "Failed to publish $rockspec_file to LuaRocks."
            # Continue to next file if any, or let set -e handle exit
        fi
    fi
done
