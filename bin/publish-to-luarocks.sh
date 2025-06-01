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
declare -a rockspecs_to_publish=()

if [ "$1" = "--dry-run" ]; then
    DRY_RUN_ARG="--dry-run"
    shift # Consume --dry-run
fi

# All remaining arguments are rockspec files
for arg in "$@"; do
    if [ -n "$arg" ]; then # Ensure argument is not an empty string
        rockspecs_to_publish+=("$arg")
    fi
done

if [ "${#rockspecs_to_publish[@]}" -eq 0 ]; then
    print_error_stderr "Error: No valid rockspec files were provided for publishing."
fi

for rockspec_file in "${rockspecs_to_publish[@]}"; do
    if [ ! -f "$rockspec_file" ]; then
        print_error_stderr "Rockspec file not found: $rockspec_file"
    fi

    print_status_stderr "Preparing to publish ${rockspec_file} to LuaRocks..."

    # Determine API key (scoped per rockspec in case of interactive prompt)
    CURRENT_LUAROCKS_API_KEY=""
    if [ -z "$LUAROCKS_API_KEY" ]; then # Check environment variable
        print_warning_stderr "LUAROCKS_API_KEY environment variable not set for $rockspec_file."
        if [ "$DRY_RUN_ARG" != "--dry-run" ]; then
            read -p "Enter your LuaRocks API key for $rockspec_file (or press Enter to skip this file): " -s API_KEY_INPUT >&2
            echo >&2 # Newline after secret input
            if [ -z "$API_KEY_INPUT" ]; then
                print_warning_stderr "Skipping $rockspec_file due to no API key provided."
                continue # Skip to the next rockspec file
            fi
            CURRENT_LUAROCKS_API_KEY="$API_KEY_INPUT"
        else
            print_warning_stderr "DRY RUN: Would need LUAROCKS_API_KEY for $rockspec_file."
            # For dry run, we don't need a real key, but we act as if we would proceed
        fi
    else
        CURRENT_LUAROCKS_API_KEY="$LUAROCKS_API_KEY"
    fi

    if [ "$DRY_RUN_ARG" = "--dry-run" ]; then
        print_warning_stderr "DRY RUN: Would upload: luarocks upload $rockspec_file --api-key=***"
    else
        if [ -z "$CURRENT_LUAROCKS_API_KEY" ]; then # Should only happen if env var not set AND skipped input in non-dry run
            print_warning_stderr "No API key available for $rockspec_file. Skipping upload."
            continue
        fi
        print_status_stderr "Uploading $rockspec_file to LuaRocks..."
        if luarocks upload "$rockspec_file" --api-key="$CURRENT_LUAROCKS_API_KEY"; then
            print_status_stderr "Successfully published $rockspec_file to LuaRocks!"
        else
            # Do not exit immediately, allow other rockspecs to be processed if any.
            print_error_stderr "Failed to publish $rockspec_file to LuaRocks. See errors above."
            # If you want to stop on first failure, remove the print_error_stderr and let set -e handle it, or exit 1 here.
        fi
    fi
done
