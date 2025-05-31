#!/usr/bin/env bash
set -e

# Release Orchestrator Script for lual
# Usage: ./bin/release.sh [--dry-run]

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
PROJECT_ROOT="$SCRIPT_DIR/.."
cd "$PROJECT_ROOT"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check for dry-run flag
DRY_RUN=""
if [ "$1" = "--dry-run" ]; then
    DRY_RUN="--dry-run"
    print_warning "DRY RUN MODE - No actual changes will be made"
fi

# Check if VERSION file exists
VERSION_FILE="releases/VERSION"
if [ ! -f "$VERSION_FILE" ]; then
    print_error "VERSION file not found: $VERSION_FILE"
    exit 1
fi

# Read current version
CURRENT_VERSION=$(cat "$VERSION_FILE" | tr -d '\n' | tr -d '\r')
if [ -z "$CURRENT_VERSION" ]; then
    print_error "VERSION file is empty: $VERSION_FILE"
    exit 1
fi

print_status "Current version: $CURRENT_VERSION"

# Ask user what to do
echo
print_status "Choose action:"
echo "1. Use current version ($CURRENT_VERSION)"
echo "2. Bump version"
echo

while true; do
    read -p "Select action (1-2): " -n 1 -r choice
    echo

    case $choice in
    1)
        print_status "Using current version: $CURRENT_VERSION"
        NEW_VERSION="$CURRENT_VERSION"
        break
        ;;
    2)
        # Get bump type from user
        echo
        print_status "Select bump type:"
        echo "1. Major ($(./bin/bump-version major))"
        echo "2. Minor ($(./bin/bump-version minor))"
        echo "3. Patch ($(./bin/bump-version patch))"
        echo

        while true; do
            read -p "Select bump type (1-3): " -n 1 -r bump_choice
            echo

            case $bump_choice in
            1)
                BUMP_TYPE="major"
                break
                ;;
            2)
                BUMP_TYPE="minor"
                break
                ;;
            3)
                BUMP_TYPE="patch"
                break
                ;;
            *)
                print_error "Invalid choice. Please select 1, 2, or 3."
                ;;
            esac
        done

        # Get new version from bump-version script
        NEW_VERSION=$(./bin/bump-version "$BUMP_TYPE")
        print_status "$BUMP_TYPE version bump: $CURRENT_VERSION → $NEW_VERSION"

        # Update VERSION file
        if [ -z "$DRY_RUN" ]; then
            echo "$NEW_VERSION" >"$VERSION_FILE"
            print_success "VERSION file updated: $NEW_VERSION"
        else
            print_status "Would update VERSION file to: $NEW_VERSION"
        fi
        break
        ;;
    *)
        print_error "Invalid choice. Please select 1 or 2."
        ;;
    esac
done

# Generate rockspecs
echo
print_status "Generating rockspecs..."
if [ -z "$DRY_RUN" ]; then
    if ./bin/create-specs; then
        print_success "Rockspecs generated successfully!"
    else
        print_error "Failed to generate rockspecs"
        exit 1
    fi
else
    print_status "Would run: ./bin/create-specs"
fi

# Run the actual release
echo
print_status "Running release process..."
if [ -z "$DRY_RUN" ]; then
    ./bin/_release.sh "$NEW_VERSION"
else
    ./bin/_release.sh "$NEW_VERSION" --dry-run
fi
