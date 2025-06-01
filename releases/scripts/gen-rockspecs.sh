#!/usr/bin/env bash
#
# Script: gen-rockspecs.sh
# Purpose: Generates the main rockspec file for the project from its template.
#          It replaces placeholders in the template with actual values for package name and version.
#          It also validates the generated rockspec using `luarocks lint`.
#          Outputs the filename of the generated rockspec to stdout.
#
# Usage: ./gen-rockspecs.sh
#   (No arguments, relies on environment variables)
#
# Environment Variables Expected (set by caller, e.g., do-release.sh):
#   - PROJECT_ROOT_ABS    : Absolute path to the project root.
#   - PKG_NAME            : Base name of the main package.
#   - FINAL_VERSION       : The version string for the release (e.g., "0.9.0").
#   - SPEC_TEMPLATE_ABS   : Absolute path to the main rockspec template (e.g., .../releases/spec.template).
#
# Called by: releases/do-release.sh
# Assumptions:
#   - CWD is PROJECT_ROOT_ABS when this script is called.
#   - Rockspec template (spec.template) exists at the path specified by SPEC_TEMPLATE_ABS.
#   - Template uses "@@PACKAGE_NAME@@" for the package name placeholder and
#     "@@VERSION-1" for the version placeholder (where -1 is the rockspec revision).
#   - Rockspec is generated in the CWD (PROJECT_ROOT_ABS).
#
set -e

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
if [ -z "$SPEC_TEMPLATE_ABS" ]; then
    echo "Error: SPEC_TEMPLATE_ABS env var not set." >&2
    exit 1
fi

# --- Configuration ---
ROCK_REVISION="1"

# Output rockspec file will be in PROJECT_ROOT_ABS (current CWD)
MAIN_ROCKSPEC_FILENAME="${PKG_NAME}-${FINAL_VERSION}-${ROCK_REVISION}.rockspec"

BLUE='\033[0;34m'
NC='\033[0m'
print_status_stderr() { echo -e "${BLUE}[INFO]${NC} $1" >&2; }

# ---- Generate main package rockspec ----
# Template is at absolute path, output is to CWD (PROJECT_ROOT_ABS)
print_status_stderr "Generating ${MAIN_ROCKSPEC_FILENAME} from ${SPEC_TEMPLATE_ABS}..."
if [ ! -f "$SPEC_TEMPLATE_ABS" ]; then
    echo "Error: Main template not found: $SPEC_TEMPLATE_ABS" >&2
    exit 1
fi

cp "$SPEC_TEMPLATE_ABS" "$MAIN_ROCKSPEC_FILENAME"
sed -i.bak "s|package = \"@@PACKAGE_NAME@@\"|package = \"${PKG_NAME}\"|g" "$MAIN_ROCKSPEC_FILENAME"
sed -i.bak "s|version = \"@@VERSION-1\"|version = \"${FINAL_VERSION}-${ROCK_REVISION}\"|g" "$MAIN_ROCKSPEC_FILENAME"
rm -f "${MAIN_ROCKSPEC_FILENAME}.bak"

print_status_stderr "Validating ${MAIN_ROCKSPEC_FILENAME}..."
if ! luarocks lint "$MAIN_ROCKSPEC_FILENAME"; then # Lint relative to CWD
    echo "Error: Validation failed for ${MAIN_ROCKSPEC_FILENAME}" >&2
    exit 1
fi
echo "$MAIN_ROCKSPEC_FILENAME" # Output just the filename
