#!/usr/bin/env bash
#
# Script: build-rocks.sh
# Purpose: Packs one or more rockspec files into .rock (binary/source rock) files using `luarocks pack`.
#          This step also serves as a validation that the rockspec is buildable.
#          Outputs the exact name(s) of the created .rock file(s) to stdout, one per line.
#          Typically, for a source rockspec, this will be <package_name>-<version>-<revision>.src.rock
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

    base_name=$(basename "$rockspec_file" .rockspec)

    # Attempt to remove any pre-existing rock for this exact version to ensure we identify the newly created one.
    rm -f "${base_name}.src.rock" "${base_name}.all.rock" "${base_name}"*.rock

    # Suppress stdout from luarocks pack, as we determine the filename ourselves.
    # Error output from luarocks pack will still go to stderr.
    luarocks pack "$rockspec_file" >/dev/null

    created_rock_file=""
    if [ -f "${base_name}.src.rock" ]; then
        created_rock_file="${base_name}.src.rock"
    elif [ -f "${base_name}.all.rock" ]; then
        created_rock_file="${base_name}.all.rock"
    else
        found_rocks=(${base_name}*.rock)
        if [ ${#found_rocks[@]} -gt 0 ]; then
            created_rock_file="${found_rocks[0]}"
        fi
    fi

    if [ -z "$created_rock_file" ] || [ ! -f "$created_rock_file" ]; then
        echo "Error: Failed to create or find .rock file for ${rockspec_file} (expected pattern like ${base_name}.src.rock or ${base_name}.all.rock after running luarocks pack)" >&2
        exit 1
    fi

    print_status_stderr "  Packed rock identified as: $created_rock_file"
    echo "$created_rock_file" # Output the exact created rock filename
done
