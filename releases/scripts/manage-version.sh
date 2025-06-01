#!/usr/bin/env bash
set -e

# Manages version: reads current, asks to use or bump, writes back.
# Outputs the final version string.
# Usage: ./manage-version.sh <version_file_abs_path> <scripts_dir_abs_path> [--use-current | --bump-type <patch|minor|major> <bump_value_if_any>]

# Arguments for explicit pathing, reducing reliance on CWD or relative SCRIPT_DIR for critical files.
VERSION_FILE_PATH_ARG=$1
SCRIPTS_DIR_ARG=$2
VERSION_ACTION=$3
BUMP_TYPE_ARG=$4

# Colors for output (defined here as this script might be called standalone for testing)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() { echo -e "${BLUE}[INFO]${NC} $1" >&2; }
print_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
    exit 1
}

if [ -z "$VERSION_FILE_PATH_ARG" ]; then print_error "Version file path argument not provided."; fi
if [ -z "$SCRIPTS_DIR_ARG" ]; then print_error "Scripts directory path argument not provided."; fi

if [ ! -f "$VERSION_FILE_PATH_ARG" ]; then
    print_error "VERSION file not found at [$VERSION_FILE_PATH_ARG] (PWD is [$(pwd)])"
fi

CURRENT_VERSION=$(cat "$VERSION_FILE_PATH_ARG" | tr -d '\n' | tr -d '\r')
if [ -z "$CURRENT_VERSION" ]; then print_error "VERSION file is empty: [$VERSION_FILE_PATH_ARG]"; fi

NEW_VERSION="$CURRENT_VERSION"

if [ "$VERSION_ACTION" = "--use-current" ]; then
    print_status "Using current version from VERSION file: $CURRENT_VERSION (as per --use-version-file flag)"
elif [ "$VERSION_ACTION" = "--bump-type" ]; then
    if [[ ! "$BUMP_TYPE_ARG" =~ ^(patch|minor|major)$ ]]; then print_error "Invalid bump type '$BUMP_TYPE_ARG'."; fi
    print_status "Bumping version by '$BUMP_TYPE_ARG' (as per --bump flag)..."
    NEW_VERSION=$("$SCRIPTS_DIR_ARG/bump-version" "$BUMP_TYPE_ARG" "$CURRENT_VERSION")
    print_status "$BUMP_TYPE_ARG version bump: $CURRENT_VERSION → $NEW_VERSION"
else
    print_status "Current version: $CURRENT_VERSION"
    echo >&2
    print_status "Choose action:"
    echo "1. Use current version ($CURRENT_VERSION)" >&2
    echo "2. Bump version" >&2
    echo >&2

    while true; do
        read -p "Select action (1-2): " -n 1 -r choice >&2
        echo >&2
        case $choice in
        1)
            print_status "Using current version: $CURRENT_VERSION"
            NEW_VERSION="$CURRENT_VERSION"
            break
            ;;
        2)
            echo >&2
            print_status "Select bump type:"
            PATCH_BUMP=$("$SCRIPTS_DIR_ARG/bump-version" patch "$CURRENT_VERSION")
            MINOR_BUMP=$("$SCRIPTS_DIR_ARG/bump-version" minor "$CURRENT_VERSION")
            MAJOR_BUMP=$("$SCRIPTS_DIR_ARG/bump-version" major "$CURRENT_VERSION")
            echo "1. Patch ($PATCH_BUMP)" >&2
            echo "2. Minor ($MINOR_BUMP)" >&2
            echo "3. Major ($MAJOR_BUMP)" >&2
            echo >&2
            while true; do
                read -p "Select bump type (1-3): " -n 1 -r bump_choice >&2
                echo >&2
                case $bump_choice in
                1)
                    BUMP_TYPE="patch"
                    NEW_VERSION="$PATCH_BUMP"
                    break
                    ;;
                2)
                    BUMP_TYPE="minor"
                    NEW_VERSION="$MINOR_BUMP"
                    break
                    ;;
                3)
                    BUMP_TYPE="major"
                    NEW_VERSION="$MAJOR_BUMP"
                    break
                    ;;
                *) print_error "Invalid choice. Please select 1, 2, or 3." ;;
                esac
            done
            print_status "$BUMP_TYPE version bump: $CURRENT_VERSION → $NEW_VERSION"
            break
            ;;
        *) print_error "Invalid choice. Please select 1 or 2." ;;
        esac
    done
fi

if [ "$NEW_VERSION" != "$CURRENT_VERSION" ]; then
    print_status "Updating VERSION file ($VERSION_FILE_PATH_ARG) to: $NEW_VERSION"
    echo "$NEW_VERSION" >"$VERSION_FILE_PATH_ARG"
fi

echo "$NEW_VERSION"
