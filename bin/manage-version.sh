#!/usr/bin/env bash
set -e

# Manages version: reads current, asks to use or bump, writes back.
# Outputs the final version string.
# Accepts optional args: --use-current or --bump-type <patch|minor|major>

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
PROJECT_ROOT="$SCRIPT_DIR/.."
cd "$PROJECT_ROOT" # Ensure we are in the project root

VERSION_ACTION=$1
BUMP_TYPE_ARG=$2

VERSION_FILE="releases/VERSION"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() { echo -e "${BLUE}[INFO]${NC} $1" >&2; } # Output to stderr for prompts
print_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
    exit 1
}

if [ ! -f "$VERSION_FILE" ]; then
    print_error "VERSION file not found: $VERSION_FILE"
fi

CURRENT_VERSION=$(cat "$VERSION_FILE" | tr -d '\n' | tr -d '\r')
if [ -z "$CURRENT_VERSION" ]; then
    print_error "VERSION file is empty: $VERSION_FILE"
fi

NEW_VERSION="$CURRENT_VERSION"

if [ "$VERSION_ACTION" = "--use-current" ]; then
    print_status "Using current version from VERSION file: $CURRENT_VERSION (as per --use-version-file flag)"
    NEW_VERSION="$CURRENT_VERSION"
elif [ "$VERSION_ACTION" = "--bump-type" ]; then
    if [[ ! "$BUMP_TYPE_ARG" =~ ^(patch|minor|major)$ ]]; then
        print_error "Invalid bump type '$BUMP_TYPE_ARG' provided to manage-version.sh. Must be patch, minor, or major."
    fi
    print_status "Bumping version by '$BUMP_TYPE_ARG' (as per --bump flag)..."
    NEW_VERSION=$("$SCRIPT_DIR/bump-version" "$BUMP_TYPE_ARG" "$CURRENT_VERSION")
    print_status "$BUMP_TYPE_ARG version bump: $CURRENT_VERSION \u2192 $NEW_VERSION"
else
    # Interactive mode if no specific action flag is given
    print_status "Current version: $CURRENT_VERSION"
    echo >&2 # Newline for readability
    print_status "Choose action:"
    echo "1. Use current version ($CURRENT_VERSION)" >&2
    echo "2. Bump version" >&2
    echo >&2

    while true; do
        read -p "Select action (1-2): " -n 1 -r choice >&2
        echo >&2 # Newline after choice

        case $choice in
        1)
            print_status "Using current version: $CURRENT_VERSION"
            NEW_VERSION="$CURRENT_VERSION"
            break
            ;;
        2)
            echo >&2
            print_status "Select bump type:"
            PATCH_BUMP=$("$SCRIPT_DIR/bump-version" patch "$CURRENT_VERSION")
            MINOR_BUMP=$("$SCRIPT_DIR/bump-version" minor "$CURRENT_VERSION")
            MAJOR_BUMP=$("$SCRIPT_DIR/bump-version" major "$CURRENT_VERSION")

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
            print_status "$BUMP_TYPE version bump: $CURRENT_VERSION \u2192 $NEW_VERSION"
            break
            ;;
        *)
            print_error "Invalid choice. Please select 1 or 2."
            ;;
        esac
    done
fi

if [ "$NEW_VERSION" != "$CURRENT_VERSION" ]; then
    print_status "Updating VERSION file to: $NEW_VERSION"
    echo "$NEW_VERSION" >"$VERSION_FILE"
fi

# Output the final version to stdout for the calling script
echo "$NEW_VERSION"
