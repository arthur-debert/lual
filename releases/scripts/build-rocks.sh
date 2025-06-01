#!/usr/bin/env bash
#
# Script: build-rocks.sh
# Purpose: Packs one or more rockspec files into .rock (binary/source rock) files using `luarocks pack`.
#          This step also serves as a validation that the rockspec is buildable.
#          Outputs representative names of the created .rock files to stdout, one per line
#          (e.g., <package_name>-<version>-<revision>.rock, actual file might be .src.rock or .all.rock).
#
# Usage: ./build-rocks.sh <rockspec_file1> [rockspec_file2 ...]
#   <rockspec_fileN> : Filename(s) of the rockspec(s) to pack (expected to be in CWD).
#
# Environment Variables Expected (implicitly, via CWD):
#   - CWD should be PROJECT_ROOT_ABS, where rockspec files are located and .rock files will be created.
#
# Called by: releases/do-release.sh
# Assumptions:
#   - `luarocks` command is available.
#   - Rockspec files passed as arguments exist in the Current Working Directory.
#
set -e

# Assumes CWD is the project root where rockspec files are located.

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
        echo "Error: Rockspec file not found: $rockspec_file (CWD: $(pwd))" >&2
        exit 1
    fi
    print_status_stderr "Packing ${rockspec_file}..."
    # luarocks pack can produce multiple files (e.g., .src.rock, .all.rock, or arch-specific)
    # We'll just run the command and list what's new, or derive the primary name.
    luarocks pack "$rockspec_file"

    # Derive base rock file name
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

    # Output a representative name; luarocks pack might create arch-specific or .src.rock files.
    # The calling script typically lists the primary generated rockspec filename again.
    # This output confirms a .rock file corresponding to the base name was created.
    echo "${base_name}.rock" # Output a representative name
done
