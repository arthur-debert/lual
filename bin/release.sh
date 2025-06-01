#!/usr/bin/env bash
set -e

# Release Orchestrator Script for lual
# Usage: ./bin/release.sh [--dry-run]
#
#
# This script automates the entire release process for the lual library.
# 1. Version Management:
#   - Will confirm if the version in VERSION is the right one or offer to bump it.
#   - Automated bumping (will ask for patch/minor/major)
#   - Will update the VERSION file with the new version.
# 2. Rockspec Generation:
#  - Will generate the main rockspec and extras rockspec (if applicable).
#  - Will commit the VERSION file and generated rockspecs.
# 3. Release Process:
#  - Will run the actual release script (_release.sh) with the new version.
#   - Generates git tags and pushes them.
#   - Use luarocks to upload the rockspecs to the luarocks server.
#   - Creates a GitHub release with the new version<D-x>
#
# This script supposed:
# -- releases
#   ├── ${LIBNAME}.spec.template -> main rockspec template
#   ├── ${LIBNAME}extras.spec.template -> (optional) extras
#   └── VERSION -> keeps current version, can be auto-generated

1 directory, 5 files

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

# Check for clean working directory. This check is vital for both real and dry runs.
print_status "Checking for clean working directory..."
if [ -n "$(git status --porcelain)" ]; then # If porcelain output is not empty, there are changes
    print_error "Your working directory or staging area is not clean."
    print_error "Please commit or stash any pending changes before running the release script."
    echo -e "${YELLOW}Current git status:${NC}"
    git status # Provides a more readable summary than just porcelain
    exit 1
else
    print_success "Working directory is clean. Proceeding."
fi

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

# Store original version for potential rollback
ORIGINAL_VERSION="$CURRENT_VERSION"

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
        echo "1. Patch ($(./bin/bump-version patch))"
        echo "2. Minor ($(./bin/bump-version minor))"
        echo "3. Major ($(./bin/bump-version major))"
        echo

        while true; do
            read -p "Select bump type (1-3): " -n 1 -r bump_choice
            echo

            case $bump_choice in
            1)
                BUMP_TYPE="patch"
                break
                ;;
            2)
                BUMP_TYPE="minor"
                break
                ;;
            3)
                BUMP_TYPE="major"
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

# Commit the changes (VERSION file and rockspecs) before running release
echo
print_status "Processing VERSION file and rockspecs for git commit..."
if [ -z "$DRY_RUN" ]; then
    print_status "Staging VERSION file and generated rockspecs..."
    # Ensure set -e handles failure if files don't exist (create-specs should have made them)
    git add releases/VERSION "lual-${NEW_VERSION}-1.rockspec" "lualextras-${NEW_VERSION}-1.rockspec"

    # Check if there are any staged changes
    # `git diff --cached --quiet` exits 0 if no staged changes, 1 if there are.
    if git diff --cached --quiet; then
        print_status "No new changes to VERSION file or rockspecs were staged. Nothing to commit."
    else
        print_status "Committing staged changes..."
        git commit -m "Prepare release v${NEW_VERSION}"

        print_status "Pushing changes..."
        git push origin "$(git branch --show-current)"

        print_success "Changes committed and pushed"
    fi
else # DRY_RUN
    print_status "Would stage (if changed/new):"
    print_status "  - releases/VERSION"
    print_status "  - lual-${NEW_VERSION}-1.rockspec"
    print_status "  - lualextras-${NEW_VERSION}-1.rockspec"
    print_status "Would commit (if anything was staged) with message: Prepare release v${NEW_VERSION}"
    print_status "Would push changes (if committed)"
fi

# Run the actual release
echo
print_status "Running release process..."
if [ -z "$DRY_RUN" ]; then
    if ./bin/_release.sh "$NEW_VERSION"; then
        print_success "Release completed successfully!"
    else
        print_error "Release failed! Rolling back version changes..."

        # Revert VERSION file if it was changed
        if [ "$NEW_VERSION" != "$ORIGINAL_VERSION" ]; then
            echo "$ORIGINAL_VERSION" >"$VERSION_FILE"
            print_status "Reverted VERSION file to: $ORIGINAL_VERSION"

            # Commit the rollback
            git add releases/VERSION
            git commit -m "Rollback version to $ORIGINAL_VERSION after failed release"
            git push origin "$(git branch --show-current)"
            print_status "Rollback committed and pushed"
        fi

        exit 1
    fi
else
    ./bin/_release.sh "$NEW_VERSION" --dry-run
fi
