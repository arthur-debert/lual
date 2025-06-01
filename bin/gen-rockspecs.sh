#!/usr/bin/env bash
set -e

# Generates rockspec files from templates for the given version.
# Usage: ./gen-rockspecs.sh <pkg_name> <version> [--with-extras]
# Outputs paths to generated rockspec files, one per line.

if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Error: Package name and version arguments are required." >&2
    echo "Usage: ./gen-rockspecs.sh <pkg_name> <version> [--with-extras]" >&2
    exit 1
fi

PKG_NAME_ARG=$1
NEW_VERSION=$2
WITH_EXTRAS_ARG=$3 # Will be "--with-extras" or empty

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
PROJECT_ROOT="$SCRIPT_DIR/.."
cd "$PROJECT_ROOT" # Ensure we are in the project root

# --- Configuration ---
# REPO_URL & GIT_TAG would be used if templates had placeholders for them.
# For now, templates manage these themselves or they are hardcoded.
ROCK_REVISION="1" # This is now part of the version string directly.

MAIN_TEMPLATE="releases/spec.template"
MAIN_ROCKSPEC="${PKG_NAME_ARG}-${NEW_VERSION}-${ROCK_REVISION}.rockspec"

EXTRAS_NAME="${PKG_NAME_ARG}extras" # Construct extras package name
EXTRAS_TEMPLATE="releases/extras.spec.template"
EXTRAS_ROCKSPEC="${EXTRAS_NAME}-${NEW_VERSION}-${ROCK_REVISION}.rockspec"

# Colors (optional, for stderr messages if any)
BLUE='\033[0;34m'
NC='\033[0m'
print_status_stderr() { echo -e "${BLUE}[INFO]${NC} $1" >&2; }

# ---- Generate main package rockspec ----
print_status_stderr "Generating ${MAIN_ROCKSPEC} from ${MAIN_TEMPLATE}..."
if [ ! -f "$MAIN_TEMPLATE" ]; then
    echo "Error: Main template not found: $MAIN_TEMPLATE" >&2
    exit 1
fi

cp "$MAIN_TEMPLATE" "$MAIN_ROCKSPEC"
sed -i.bak "s|package = \"@@PACKAGE_NAME@@\"|package = \"${PKG_NAME_ARG}\"|g" "$MAIN_ROCKSPEC"
sed -i.bak "s|version = \"@@VERSION-1\"|version = \"${NEW_VERSION}-${ROCK_REVISION}\"|g" "$MAIN_ROCKSPEC"
rm -f "${MAIN_ROCKSPEC}.bak"

print_status_stderr "Validating ${MAIN_ROCKSPEC}..."
if ! luarocks lint "$MAIN_ROCKSPEC"; then
    echo "Error: Validation failed for ${MAIN_ROCKSPEC}" >&2
    exit 1
fi
echo "$MAIN_ROCKSPEC" # Output path to stdout

# ---- Generate extras rockspec (if requested) ----
if [ "$WITH_EXTRAS_ARG" = "--with-extras" ]; then
    print_status_stderr "Generating ${EXTRAS_ROCKSPEC} from ${EXTRAS_TEMPLATE}..."
    if [ ! -f "$EXTRAS_TEMPLATE" ]; then
        echo "Error: Extras template not found: $EXTRAS_TEMPLATE" >&2
        exit 1
    fi

    cp "$EXTRAS_TEMPLATE" "$EXTRAS_ROCKSPEC"
    sed -i.bak "s|package = \"@@PACKAGE_NAME@@\"|package = \"${EXTRAS_NAME}\"|g" "$EXTRAS_ROCKSPEC"
    sed -i.bak "s|version = \"@@VERSION-1\"|version = \"${NEW_VERSION}-${ROCK_REVISION}\"|g" "$EXTRAS_ROCKSPEC"
    rm -f "${EXTRAS_ROCKSPEC}.bak"

    print_status_stderr "Validating ${EXTRAS_ROCKSPEC}..."
    if ! luarocks lint "$EXTRAS_ROCKSPEC"; then
        echo "Error: Validation failed for ${EXTRAS_ROCKSPEC}" >&2
        exit 1
    fi
    echo "$EXTRAS_ROCKSPEC" # Output path to stdout
fi
