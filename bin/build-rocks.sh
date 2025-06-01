#!/usr/bin/env bash
set -e

# Packs rockspec files into .rock files.
# Usage: ./build-rocks.sh <rockspec_file1> [rockspec_file2 ...]
# Outputs paths to created .rock files (or the base name if arch-specific).

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
PROJECT_ROOT="$SCRIPT_DIR/.."
cd "$PROJECT_ROOT" # Ensure we are in the project root

# Colors (optional, for stderr messages if any)
BLUE='\033[0;34m'
NC='\033[0m'
print_status_stderr() { echo -e "${BLUE}[INFO]${NC} $1" >&2; }

if [ "$#" -eq 0 ]; then
    echo "Error: At least one rockspec file argument is required." >&2
    exit 1
fi

for rockspec_file in "$@"; do
    if [ ! -f "$rockspec_file" ]; then
        echo "Error: Rockspec file not found: $rockspec_file" >&2
        exit 1
    fi
    print_status_stderr "Packing ${rockspec_file}..."
    # luarocks pack can produce multiple files (e.g., .src.rock, .all.rock, or arch-specific)
    # We'll just run the command and list what's new, or derive the primary name.
    luarocks pack "$rockspec_file"

    # Derive base rock file name (e.g. lual-0.8.8-1 from lual-0.8.8-1.rockspec)
    # This is a simple way; actual packed files might have .all.rock or .src.rock
    base_name=$(basename "$rockspec_file" .rockspec)

    # Check if at least one rock file was created for this base name
    # This is a heuristic, as 'luarocks pack' output can vary.
    # A more robust way would be to parse 'luarocks pack' output or know expected suffixes.
    created_rocks=$(ls "${base_name}"*.rock 2>/dev/null)
    if [ -z "$created_rocks" ]; then
        echo "Error: Failed to create .rock file for ${rockspec_file} (or could not find it as ${base_name}*.rock)" >&2
        exit 1
    fi

    # Output the base name; the caller can infer the actual .rock files
    # Or list all found: echo "$created_rocks"
    echo "${base_name}.rock" # Output a representative name
done
