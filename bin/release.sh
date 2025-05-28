#!/usr/bin/env bash
set -e

# LuaRocks Release Script for lual
# Usage: ./bin/release.sh <version> [--dry-run]
# Example: ./bin/release.sh 0.2.0

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

# Check if version is provided
if [ -z "$1" ]; then
    print_error "Usage: $0 <version> [--dry-run]"
    print_error "Example: $0 0.2.0"
    exit 1
fi

NEW_VERSION="$1"
DRY_RUN=""
if [ "$2" = "--dry-run" ]; then
    DRY_RUN="--dry-run"
    print_warning "DRY RUN MODE - No actual changes will be made"
fi

# Validate version format (basic semantic versioning)
if ! echo "$NEW_VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    print_error "Version must follow semantic versioning format: MAJOR.MINOR.PATCH (e.g., 0.2.0)"
    exit 1
fi

# Find current rockspec
CURRENT_ROCKSPEC=$(find . -maxdepth 1 -name "lual-*.rockspec" | head -1)
if [ -z "$CURRENT_ROCKSPEC" ]; then
    print_error "No current rockspec found (lual-*.rockspec)"
    exit 1
fi

NEW_ROCKSPEC="lual-${NEW_VERSION}-1.rockspec"

print_status "Current rockspec: $CURRENT_ROCKSPEC"
print_status "New rockspec: $NEW_ROCKSPEC"
print_status "New version: $NEW_VERSION"

# Check if we're on main/master branch
CURRENT_BRANCH=$(git branch --show-current)
if [ "$CURRENT_BRANCH" != "main" ] && [ "$CURRENT_BRANCH" != "master" ]; then
    print_warning "You're not on main/master branch (current: $CURRENT_BRANCH)"
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Check for uncommitted changes
if ! git diff-index --quiet HEAD --; then
    print_error "You have uncommitted changes. Please commit or stash them first."
    exit 1
fi

# Check if tag already exists
if git tag -l | grep -q "^v${NEW_VERSION}$"; then
    print_error "Tag v${NEW_VERSION} already exists"
    exit 1
fi

# Validate current rockspec
print_status "Validating current rockspec..."
if [ -z "$DRY_RUN" ]; then
    luarocks lint "$CURRENT_ROCKSPEC"
fi

# Update dependencies to ensure fresh environment
print_status "Updating dependencies with fresh install..."
if [ -z "$DRY_RUN" ]; then
    ./bin/update-deps.sh
else
    print_status "Would run: ./bin/update-deps.sh"
fi

# Create new version using luarocks
print_status "Creating new rockspec version..."
if [ -z "$DRY_RUN" ]; then
    luarocks new_version "$CURRENT_ROCKSPEC" "$NEW_VERSION"
else
    print_status "Would run: luarocks new_version $CURRENT_ROCKSPEC $NEW_VERSION"
fi

# Update the source.url in the new rockspec to point to the correct repository
# (luarocks new_version might not set this correctly)
if [ -z "$DRY_RUN" ]; then
    # Get the repository URL from git
    REPO_URL=$(git config --get remote.origin.url)
    if [[ "$REPO_URL" == git@* ]]; then
        # Convert SSH URL to HTTPS
        REPO_URL=$(echo "$REPO_URL" | sed 's/git@github.com:/https:\/\/github.com\//')
        REPO_URL=$(echo "$REPO_URL" | sed 's/\.git$//')
    fi

    print_status "Updating source URL in rockspec to: $REPO_URL"

    # Update the rockspec with correct source URL and tag
    sed -i.bak "s|url = \".*\"|url = \"git+${REPO_URL}\"|" "$NEW_ROCKSPEC"
    sed -i.bak "s|tag = \".*\"|tag = \"v${NEW_VERSION}\"|" "$NEW_ROCKSPEC"
    rm "${NEW_ROCKSPEC}.bak"
fi

# Validate new rockspec
print_status "Validating new rockspec..."
if [ -z "$DRY_RUN" ]; then
    luarocks lint "$NEW_ROCKSPEC"
fi

# Show what will be committed
print_status "Changes to be committed:"
if [ -z "$DRY_RUN" ]; then
    git add "$NEW_ROCKSPEC"
    git status --porcelain
else
    print_status "Would add: $NEW_ROCKSPEC"
fi

# Commit the new rockspec
print_status "Committing new rockspec..."
if [ -z "$DRY_RUN" ]; then
    git commit -m "Release v${NEW_VERSION}"
else
    print_status "Would commit with message: Release v${NEW_VERSION}"
fi

# Create and push tag
print_status "Creating and pushing tag v${NEW_VERSION}..."
if [ -z "$DRY_RUN" ]; then
    git tag "v${NEW_VERSION}"
    git push origin "v${NEW_VERSION}"
    git push origin "$CURRENT_BRANCH"
else
    print_status "Would create tag: v${NEW_VERSION}"
    print_status "Would push tag and branch"
fi

# Build and test the rock
print_status "Building rock..."
if [ -z "$DRY_RUN" ]; then
    luarocks --tree ./.luarocks make "$NEW_ROCKSPEC"
fi

# Pack the rock
print_status "Packing rock..."
if [ -z "$DRY_RUN" ]; then
    luarocks pack "$NEW_ROCKSPEC"
    ROCK_FILE="lual-${NEW_VERSION}-1.all.rock"
    if [ -f "$ROCK_FILE" ]; then
        print_success "Rock created: $ROCK_FILE"
    fi
fi

# Clean up old rockspec (optional)
print_warning "Old rockspec: $CURRENT_ROCKSPEC"
if [ -z "$DRY_RUN" ]; then
    read -p "Remove old rockspec? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm "$CURRENT_ROCKSPEC"
        git add "$CURRENT_ROCKSPEC"
        git commit -m "Remove old rockspec $CURRENT_ROCKSPEC"
        git push origin "$CURRENT_BRANCH"
        print_success "Old rockspec removed"
    fi
fi

print_success "Release v${NEW_VERSION} prepared successfully!"
echo
print_status "Next steps:"
echo "1. Test the rock: luarocks install $NEW_ROCKSPEC"
echo "2. Publish to LuaRocks: luarocks upload $NEW_ROCKSPEC --api-key=YOUR_API_KEY"
echo "3. Create GitHub release (optional)"
echo
print_status "Rock file: lual-${NEW_VERSION}-1.all.rock"
print_status "Rockspec: $NEW_ROCKSPEC"
