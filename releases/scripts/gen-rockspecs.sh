#!/usr/bin/env bash
#
# Script: gen-rockspecs.sh
# Purpose: Creates the final, canonically named, buildable rockspec file
#          (e.g., <PKG_NAME>-<FINAL_VERSION>-1.rockspec) for a release.
#          It copies a source spec file (which can be spec.template or a user-provided .rockspec file)
#          to the canonical name in the project root. It then uses `sed` to ensure that the
#          'package' and 'version' fields within the content of this new file are correctly set
#          to the values from the PKG_NAME and FINAL_VERSION environment variables (with a -1 revision).
#          Finally, it validates the generated rockspec using `luarocks lint`.
# Outputs: The filename of the generated and validated rockspec to stdout.
#
# Usage: ./gen-rockspecs.sh <source_spec_file_abs_path>
#   <source_spec_file_abs_path> : Absolute path to the source spec file (e.g., releases/spec.template
#                                   or a user-provided path/to/some.rockspec) to use as a base.
#
# Environment Variables Expected (set by caller, e.g., do-release.sh):
#   - PROJECT_ROOT_ABS    : Absolute path to the project root. The new rockspec file will be created here (CWD).
#   - PKG_NAME            : The definitive package name for the output rockspec (e.g., "lual").
#   - FINAL_VERSION       : The definitive semantic version (X.Y.Z, e.g., "0.9.0") for the output rockspec.
#
# Called by: releases/do-release.sh
# Assumptions:
#   - Current Working Directory (CWD) is PROJECT_ROOT_ABS.
#   - The <source_spec_file_abs_path> exists and is readable.
#   - The source spec file contains standard 'package = "..."' and 'version = "..."' lines that
#     can be reliably updated by the script's `sed` commands.
#   - `luarocks` command is available for linting.
#
set -e

SOURCE_SPEC_FILE_ARG=$1

# Check for necessary inputs
if [ -z "$SOURCE_SPEC_FILE_ARG" ]; then
    echo "Error: Source spec file path argument not provided." >&2
    exit 1
fi
if [ ! -f "$SOURCE_SPEC_FILE_ARG" ]; then
    echo "Error: Source spec file not found at [$SOURCE_SPEC_FILE_ARG]" >&2
    exit 1
fi

# Check for necessary environment variables
if [ -z "$PROJECT_ROOT_ABS" ]; then
    echo "Error: PROJECT_ROOT_ABS env var not set." >&2
    exit 1
fi
if [ -z "$PKG_NAME" ]; then
    echo "Error: PKG_NAME env var not set." >&2
    exit 1
fi
if [ -z "$FINAL_VERSION" ]; then
    echo "Error: FINAL_VERSION env var not set." >&2
    exit 1
fi

# --- Configuration ---
ROCK_REVISION="1"

# Output rockspec file will be in PROJECT_ROOT_ABS (current CWD)
# This is the canonical name for the rockspec to be built/published.
FINAL_ROCKSPEC_FILENAME="${PKG_NAME}-${FINAL_VERSION}-${ROCK_REVISION}.rockspec"

BLUE='\033[0;34m'
NC='\033[0m'
print_status_stderr() { echo -e "${BLUE}[INFO]${NC} $1" >&2; }

# ---- Generate final package rockspec ----
print_status_stderr "Generating final rockspec ${FINAL_ROCKSPEC_FILENAME} from source ${SOURCE_SPEC_FILE_ARG}..."

cp "$SOURCE_SPEC_FILE_ARG" "$FINAL_ROCKSPEC_FILENAME"

# Replace the package name line with the actual PKG_NAME.
# This ensures 'package = "PKG_NAME"' is set, regardless of source format.
sed -i.bak -E "s/^[[:space:]]*package[[:space:]]*=[[:space:]]*[\"\\'].*[\"\\']$/package = \\\"${PKG_NAME}\\\"/g" "$FINAL_ROCKSPEC_FILENAME"

# Ensure version is set correctly to FINAL_VERSION with ROCK_REVISION in the new file
# This replaces the whole line like 'version = "anything"' with 'version = "actual_version-rev"'
sed -i.bak -E "s/^[[:space:]]*version[[:space:]]*=[[:space:]]*[\"\\'].*[\"\\']$/version = \\\"${FINAL_VERSION}-${ROCK_REVISION}\\\"/g" "$FINAL_ROCKSPEC_FILENAME"

rm -f "${FINAL_ROCKSPEC_FILENAME}.bak"

print_status_stderr "Validating ${FINAL_ROCKSPEC_FILENAME}..."
if ! luarocks lint "$FINAL_ROCKSPEC_FILENAME"; then # Lint relative to CWD
    echo "Error: Validation failed for ${FINAL_ROCKSPEC_FILENAME}" >&2
    exit 1
fi
echo "$FINAL_ROCKSPEC_FILENAME" # Output just the filename
