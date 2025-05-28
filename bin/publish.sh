#!/usr/bin/env bash
set -e

# LuaRocks Publish Script for lual
# Usage: ./bin/publish.sh [rockspec-file] [--dry-run]
# Example: ./bin/publish.sh lual-0.2.0-1.rockspec

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

# Find rockspec file
ROCKSPEC=""
DRY_RUN=""

# Parse arguments
for arg in "$@"; do
    case $arg in
    --dry-run)
        DRY_RUN="--dry-run"
        print_warning "DRY RUN MODE - No actual upload will be performed"
        ;;
    *.rockspec)
        ROCKSPEC="$arg"
        ;;
    *)
        if [ -z "$ROCKSPEC" ] && [ -f "$arg" ]; then
            ROCKSPEC="$arg"
        fi
        ;;
    esac
done

# If no rockspec specified, find the latest one
if [ -z "$ROCKSPEC" ]; then
    ROCKSPEC=$(find . -maxdepth 1 -name "lual-*.rockspec" | sort -V | tail -1)
    if [ -z "$ROCKSPEC" ]; then
        print_error "No rockspec file found. Please specify one or ensure lual-*.rockspec exists."
        exit 1
    fi
    print_status "Auto-detected rockspec: $ROCKSPEC"
fi

# Verify rockspec exists
if [ ! -f "$ROCKSPEC" ]; then
    print_error "Rockspec file not found: $ROCKSPEC"
    exit 1
fi

# Extract version from rockspec filename
VERSION=$(basename "$ROCKSPEC" | sed 's/lual-\(.*\)\.rockspec/\1/')
print_status "Publishing version: $VERSION"

# Check if API key is available
if [ -z "$LUAROCKS_API_KEY" ]; then
    print_warning "LUAROCKS_API_KEY environment variable not set"
    print_status "You can:"
    print_status "1. Set it: export LUAROCKS_API_KEY=your_api_key"
    print_status "2. Get one from: https://luarocks.org/settings/api-keys"

    if [ -z "$DRY_RUN" ]; then
        read -p "Enter your LuaRocks API key: " -s API_KEY
        echo
        if [ -z "$API_KEY" ]; then
            print_error "API key is required for publishing"
            exit 1
        fi
        LUAROCKS_API_KEY="$API_KEY"
    fi
fi

# Validate rockspec
print_status "Validating rockspec..."
if [ -z "$DRY_RUN" ]; then
    luarocks lint "$ROCKSPEC"
    print_success "Rockspec validation passed"
fi

# Check if the version tag exists in git
TAG_VERSION=$(echo "$VERSION" | sed 's/-[0-9]*$//') # Remove rockspec revision
GIT_TAG="v$TAG_VERSION"

if [ -z "$DRY_RUN" ]; then
    if ! git tag -l | grep -q "^$GIT_TAG$"; then
        print_error "Git tag $GIT_TAG not found. Please create and push the tag first:"
        print_error "  git tag $GIT_TAG"
        print_error "  git push origin $GIT_TAG"
        exit 1
    fi
    print_success "Git tag $GIT_TAG found"
fi

# Build the rock locally to test
print_status "Building rock locally for testing..."
if [ -z "$DRY_RUN" ]; then
    luarocks build "$ROCKSPEC"
    print_success "Local build successful"
fi

# Pack the rock
print_status "Packing rock..."
if [ -z "$DRY_RUN" ]; then
    luarocks pack "$ROCKSPEC"
    ROCK_FILE=$(ls lual-${VERSION}.*.rock 2>/dev/null | head -1)
    if [ -f "$ROCK_FILE" ]; then
        print_success "Rock packed: $ROCK_FILE"
    else
        print_error "Failed to create rock file"
        exit 1
    fi
fi

# Show what will be uploaded
print_status "Ready to publish:"
print_status "  Rockspec: $ROCKSPEC"
print_status "  Version: $VERSION"
if [ -n "$ROCK_FILE" ]; then
    print_status "  Rock file: $ROCK_FILE"
fi

# Confirm upload
if [ -z "$DRY_RUN" ]; then
    echo
    print_warning "This will upload your package to the public LuaRocks repository."
    print_warning "Make sure you have tested it thoroughly!"
    echo
    read -p "Continue with upload? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "Upload cancelled"
        exit 0
    fi
fi

# Upload to LuaRocks
print_status "Uploading to LuaRocks..."
if [ -z "$DRY_RUN" ]; then
    if luarocks upload "$ROCKSPEC" --api-key="$LUAROCKS_API_KEY"; then
        print_success "Successfully published to LuaRocks!"
        echo
        print_status "Your package is now available at:"
        print_status "  https://luarocks.org/modules/$(whoami)/lual"
        echo
        print_status "Users can install it with:"
        print_status "  luarocks install lual"
        echo
        print_status "Or a specific version:"
        print_status "  luarocks install lual $VERSION"
    else
        print_error "Upload failed!"
        print_status "Common issues:"
        print_status "1. Invalid API key"
        print_status "2. Version already exists"
        print_status "3. Network connectivity issues"
        print_status "4. Rockspec validation errors"
        exit 1
    fi
else
    print_status "Would upload: luarocks upload $ROCKSPEC --api-key=***"
fi

# Clean up rock file (optional)
if [ -n "$ROCK_FILE" ] && [ -f "$ROCK_FILE" ] && [ -z "$DRY_RUN" ]; then
    echo
    read -p "Remove local rock file $ROCK_FILE? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm "$ROCK_FILE"
        print_success "Local rock file removed"
    fi
fi

print_success "Publish process completed!"
