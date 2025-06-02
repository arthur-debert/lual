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
#   - PKG_NAME          : Package name (from do-release.sh env)
#   - FINAL_VERSION     : Semantic version (X.Y.Z) (from do-release.sh env)
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
RED='\033[0;31m'
NC='\033[0m'
print_status_stderr() { echo -e "${BLUE}[INFO]${NC} $1" >&2; }
print_error_stderr() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
    exit 1
}

if [ -z "$PKG_NAME" ] || [ -z "$FINAL_VERSION" ]; then
    print_error_stderr "PKG_NAME and FINAL_VERSION environment variables must be set."
fi

ROCKSPEC_REVISION="1" # Assuming rockspec revision is always 1 for packed rocks

PACKED_ROCK_FILENAMES=()

for rockspec_file_arg in "$@"; do
    if [ -z "$rockspec_file_arg" ]; then
        print_error_stderr "Empty rockspec file argument provided."
    fi
    if [ ! -f "$rockspec_file_arg" ]; then
        print_error_stderr "Rockspec file not found: $rockspec_file_arg (CWD: $(pwd))"
    fi

    print_status_stderr "Packing ${rockspec_file_arg}..."

    # Predict the output filename
    # This assumes the rockspec file itself might have a different name pattern than the final rock,
    # but the final .src.rock will follow PKG_NAME-FINAL_VERSION-ROCKSPEC_REVISION.src.rock
    PREDICTED_PACKED_ROCK_NAME="${PKG_NAME}-${FINAL_VERSION}-${ROCKSPEC_REVISION}.src.rock"

    # Run luarocks pack, redirecting its stdout to /dev/null
    # stderr will still be visible. If it fails, set -e will stop the script.
    luarocks pack "$rockspec_file_arg" >/dev/null

    # Check if the predicted file was created
    if [ -f "$PREDICTED_PACKED_ROCK_NAME" ]; then
        print_status_stderr "  Packed rock verified: $PREDICTED_PACKED_ROCK_NAME"
        PACKED_ROCK_FILENAMES+=("$PREDICTED_PACKED_ROCK_NAME")
    else
        # This might happen if luarocks pack failed silently or conventions changed
        # Or if the rockspec_file_arg was for an 'extras' package with a different PKG_NAME
        # For now, we assume PKG_NAME and FINAL_VERSION apply to all rockspecs passed.
        print_error_stderr "Packed rock file $PREDICTED_PACKED_ROCK_NAME not found after packing $rockspec_file_arg. Build failed or filename convention mismatch."
    fi
done

if [ ${#PACKED_ROCK_FILENAMES[@]} -eq 0 ]; then
    print_error_stderr "No rock files were successfully packed."
fi

echo "${PACKED_ROCK_FILENAMES[@]}" # Print the list of packed rock filenames to stdout
