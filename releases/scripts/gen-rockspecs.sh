#!/usr/bin/env bash
#
# Script: gen-rockspecs.sh
# Purpose: Generates rockspec file(s) for the project from template(s).
#          It replaces placeholders in the template(s) with actual values for package name and version.
#          It also validates the generated rockspec(s) using `luarocks lint`.
#          Outputs the filename(s) of the generated rockspec(s) to stdout, one per line.
#
# Usage: ./gen-rockspecs.sh <with_extras_flag>
#   <with_extras_flag> : Optional. If "--with-extras", generates both main and extras rockspecs.
#                        Otherwise, only generates the main rockspec.
#
# Environment Variables Expected (set by caller, e.g., do-release.sh):
#   - PROJECT_ROOT_ABS    : Absolute path to the project root.
#   - PKG_NAME            : Base name of the main package =
#   - FINAL_VERSION       : The version string for the release (e.g., "0.9.0").
#   - SPEC_TEMPLATE_ABS   : Absolute path to the main rockspec template (e.g., .../releases/spec.template).
#   - EXTRAS_TEMPLATE_ABS : Absolute path to the extras rockspec template (e.g., .../releases/extras.spec.template).
#
# Called by: releases/do-release.sh
# Assumptions:
#   - CWD is PROJECT_ROOT_ABS when this script is called.
#   - Rockspec templates (spec.template, extras.spec.template) exist at the paths specified by
#     SPEC_TEMPLATE_ABS and EXTRAS_TEMPLATE_ABS.
#   - Templates use "@@PACKAGE_NAME@@" for the package name placeholder and
#     "@@VERSION-1" for the version placeholder (where -1 is the rockspec revision).
#   - Rockspecs are generated in the CWD (PROJECT_ROOT_ABS).
#
set -e

# Generates rockspec files from templates for the given version.
# Usage: ./gen-rockspecs.sh <with_extras_flag>
# Relies on exported env vars: PROJECT_ROOT_ABS, PKG_NAME, FINAL_VERSION,
#                               SPEC_TEMPLATE_ABS, EXTRAS_TEMPLATE_ABS

WITH_EXTRAS_FLAG=$1 # Only argument now

# Check for necessary environment variables (expanded for clarity)
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
if [ -z "$EXTRAS_TEMPLATE_ABS" ]; then
    echo "Error: EXTRAS_TEMPLATE_ABS env var not set." >&2
    exit 1
fi

# --- Configuration ---
ROCK_REVISION="1"

# Output rockspec files will be in PROJECT_ROOT_ABS (current CWD)
MAIN_ROCKSPEC_FILENAME="${PKG_NAME}-${FINAL_VERSION}-${ROCK_REVISION}.rockspec"

EXTRAS_PKG_NAME="${PKG_NAME}extras"
EXTRAS_ROCKSPEC_FILENAME="${EXTRAS_PKG_NAME}-${FINAL_VERSION}-${ROCK_REVISION}.rockspec"

BLUE='\033[0;34m'
NC='\033[0m'
print_status_stderr() { echo -e "${BLUE}[INFO]${NC} $1" >&2; }

# ---- Generate main package rockspec ----
# Templates are at absolute paths, output is to CWD (PROJECT_ROOT_ABS)
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

# ---- Generate extras rockspec (if requested) ----
if [ "$WITH_EXTRAS_FLAG" = "--with-extras" ]; then
    print_status_stderr "Generating ${EXTRAS_ROCKSPEC_FILENAME} from ${EXTRAS_TEMPLATE_ABS}..."
    if [ ! -f "$EXTRAS_TEMPLATE_ABS" ]; then
        echo "Error: Extras template not found: $EXTRAS_TEMPLATE_ABS" >&2
        exit 1
    fi

    cp "$EXTRAS_TEMPLATE_ABS" "$EXTRAS_ROCKSPEC_FILENAME"
    sed -i.bak "s|package = \"@@PACKAGE_NAME@@\"|package = \"${EXTRAS_PKG_NAME}\"|g" "$EXTRAS_ROCKSPEC_FILENAME"
    sed -i.bak "s|version = \"@@VERSION-1\"|version = \"${FINAL_VERSION}-${ROCK_REVISION}\"|g" "$EXTRAS_ROCKSPEC_FILENAME"
    rm -f "${EXTRAS_ROCKSPEC_FILENAME}.bak"

    print_status_stderr "Validating ${EXTRAS_ROCKSPEC_FILENAME}..."
    if ! luarocks lint "$EXTRAS_ROCKSPEC_FILENAME"; then # Lint relative to CWD
        echo "Error: Validation failed for ${EXTRAS_ROCKSPEC_FILENAME}" >&2
        exit 1
    fi
    echo "$EXTRAS_ROCKSPEC_FILENAME" # Output just the filename
fi
