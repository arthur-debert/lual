#!/usr/bin/env bash
#
# Script: gen-rockspecs.sh
# Purpose: Creates the final buildable rockspec file (e.g., <pkg>-<ver>-1.rockspec)
#          by copying a source_spec_file (which could be spec.template or a user-provided rockspec)
#          and then ensuring the package name and version in the new file are set correctly based on
#          exported PKG_NAME and FINAL_VERSION environment variables.
#          Outputs the filename of the generated rockspec to stdout.
#
# Usage: ./gen-rockspecs.sh <source_spec_file_abs_path>
#   <source_spec_file_abs_path> : Absolute path to the spec file to use as a base for copying.
#
# Environment Variables Expected (set by caller, e.g., do-release.sh):
#   - PROJECT_ROOT_ABS    : Absolute path to the project root (where the new rockspec will be created).
#   - PKG_NAME            : Definitive package name for the output rockspec.
#   - FINAL_VERSION       : Definitive semantic version (X.Y.Z) for the output rockspec.
#
# Called by: releases/do-release.sh
# Assumptions:
#   - CWD is PROJECT_ROOT_ABS.
#   - source_spec_file_abs_path exists and is readable.
#   - The source_spec_file (typically spec.template) is expected to contain
#     'package = "@@PKG_NAME_PLACEHOLDER@@" and a version line like 'version = "X.Y.Z-R"'.
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
