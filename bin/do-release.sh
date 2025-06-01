#!/usr/bin/env bash
set -e

# Main Release Orchestrator Script for lual
# Usage: ./bin/do-release.sh [--with-extras] [--dry-run] [--use-version-file | --bump <patch|minor|major>]

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
PROJECT_ROOT="$SCRIPT_DIR/.."
cd "$PROJECT_ROOT"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# --- Argument Parsing ---
WITH_EXTRAS_FLAG=""
DRY_RUN_FLAG=""
VERSION_ACTION=""
BUMP_TYPE_ARG=""

while [[ "$#" -gt 0 ]]; do
    case $1 in
    --with-extras)
        WITH_EXTRAS_FLAG="--with-extras"
        print_status "Including lualextras in this release."
        shift # past argument
        ;;
    --dry-run)
        DRY_RUN_FLAG="--dry-run"
        print_warning "DRY RUN MODE ENABLED"
        shift # past argument
        ;;
    --use-version-file)
        if [ -n "$VERSION_ACTION" ]; then print_error "Error: --use-version-file and --bump cannot be used together."; fi
        VERSION_ACTION="--use-current"
        print_status "Using version from releases/VERSION file directly."
        shift # past argument
        ;;
    --bump)
        if [ -n "$VERSION_ACTION" ]; then print_error "Error: --use-version-file and --bump cannot be used together."; fi
        if [[ -z "$2" ]] || [[ ! "$2" =~ ^(patch|minor|major)$ ]]; then
            print_error "Error: --bump requires a type (patch, minor, or major). Example: --bump patch"
        fi
        VERSION_ACTION="--bump-type"
        BUMP_TYPE_ARG="$2"
        print_status "Will bump version by: $BUMP_TYPE_ARG"
        shift # past argument
        shift # past value
        ;;
    *)
        print_error "Unknown option: $1"
        ;;
    esac
done

# --- Step 1: Manage Version ---
print_status "Step 1: Managing version..."
# manage-version.sh will output the final version string
FINAL_VERSION=$("$SCRIPT_DIR/manage-version.sh" $VERSION_ACTION $BUMP_TYPE_ARG)
if [ -z "$FINAL_VERSION" ]; then
    print_error "Failed to determine final version from manage-version.sh"
    exit 1
fi
print_success "Version decided: $FINAL_VERSION"
echo

# --- Pre-flight Check: Verify Version Availability on LuaRocks (if not dry run) ---
if [ -z "$DRY_RUN_FLAG" ]; then
    print_status "Pre-flight Check: Verifying if version $FINAL_VERSION for 'lual' is already on LuaRocks..."
    # We assume the main package is 'lual' for this check.
    # The rockspec revision is typically -1 for new uploads.
    if luarocks search lual "$FINAL_VERSION" | grep -q "${FINAL_VERSION}-1 (rockspec)"; then
        print_error "Error: Version lual ${FINAL_VERSION}-1 is already published on LuaRocks. Please choose a different version."
        # No exit 1 here, print_error already exits
    else
        print_success "Version lual $FINAL_VERSION appears to be available on LuaRocks."
    fi
    echo
fi

# --- Step 2: Generate Rockspecs ---
print_status "Step 2: Generating rockspecs for version $FINAL_VERSION..."
# gen-rockspecs.sh will output the paths to the generated rockspec files, one per line
GENERATED_ROCKSPECS_OUTPUT=$("$SCRIPT_DIR/gen-rockspecs.sh" "$FINAL_VERSION" "$WITH_EXTRAS_FLAG")
if [ -z "$GENERATED_ROCKSPECS_OUTPUT" ]; then
    print_error "Failed to generate rockspecs."
    exit 1
fi

# Read output into an array (handles spaces in filenames if any, though unlikely for rockspecs)
mapfile -t GENERATED_ROCKSPEC_FILES < <(echo "$GENERATED_ROCKSPECS_OUTPUT")

print_success "Rockspecs generated:"
for spec_file in "${GENERATED_ROCKSPEC_FILES[@]}"; do
    print_status "  - $spec_file"
done
echo

# --- Step 3: Build (Pack) Rocks ---
print_status "Step 3: Building (packing) rocks..."
# Pass all generated rockspec files to the build script
PACKED_ROCK_FILES_OUTPUT=$("$SCRIPT_DIR/build-rocks.sh" "${GENERATED_ROCKSPEC_FILES[@]}")
if [ -z "$PACKED_ROCK_FILES_OUTPUT" ]; then
    print_error "Failed to build/pack rocks."
    exit 1
fi
mapfile -t PACKED_ROCK_FILES < <(echo "$PACKED_ROCK_FILES_OUTPUT")
print_success "Rocks packed:"
for rock_file in "${PACKED_ROCK_FILES[@]}"; do
    print_status "  - $rock_file (and any other architecture-specific variants)"
done
echo

# --- Step 4: Commit & Tag Release ---
print_status "Step 4: Committing and tagging release..."
"$SCRIPT_DIR/commit-and-tag-release.sh" "$FINAL_VERSION" "$DRY_RUN_FLAG" "${GENERATED_ROCKSPEC_FILES[@]}"
print_success "Release committed and tagged (or would be in dry run)."
echo

# --- Step 5: Publish to LuaRocks ---
print_status "Step 5: Publishing to LuaRocks..."
"$SCRIPT_DIR/publish-to-luarocks.sh" "$DRY_RUN_FLAG" "${GENERATED_ROCKSPEC_FILES[@]}"
print_success "Publish process to LuaRocks completed (or would be in dry run)."
echo

# --- Step 6: Verify on LuaRocks (if not dry run) ---
if [ -z "$DRY_RUN_FLAG" ]; then
    print_status "Step 6: Verifying packages on LuaRocks..."
    ALL_VERIFIED=true
    for spec_file in "${GENERATED_ROCKSPEC_FILES[@]}"; do
        # Extract package name from rockspec filename e.g. lual from lual-0.8.10-1.rockspec
        PKG_NAME=$(basename "$spec_file" | sed -E "s/-${FINAL_VERSION}-[0-9]+\.rockspec//")

        if [ -n "$PKG_NAME" ]; then
            print_status "Searching for ${PKG_NAME} version ${FINAL_VERSION} on LuaRocks..."
            # Check for the rockspec entry, version will include the rockspec revision (e.g. 0.8.10-1)
            if luarocks search "$PKG_NAME" "$FINAL_VERSION" | grep -q "${FINAL_VERSION}-1 (rockspec)"; then
                print_success "  Successfully found ${PKG_NAME} ${FINAL_VERSION} on LuaRocks."
            else
                print_warning "  Could not verify ${PKG_NAME} ${FINAL_VERSION} on LuaRocks immediately. It might take a few moments to appear, or there might have been an issue."
                ALL_VERIFIED=false
            fi
        else
            print_warning "Could not parse package name from ${spec_file} to verify."
            ALL_VERIFIED=false
        fi
    done
    if [ "$ALL_VERIFIED" = true ]; then
        print_success "All published packages verified on LuaRocks."
    else
        print_warning "Some packages could not be immediately verified on LuaRocks. Please check manually."
    fi
    echo
fi

print_success "--------------------------------------------------"
print_success "LUAL RELEASE PROCESS COMPLETED SUCCESSFULLY for v$FINAL_VERSION!"
print_success "--------------------------------------------------"

if [ "$DRY_RUN_FLAG" = "--dry-run" ]; then
    print_warning "Remember, this was a DRY RUN. No permanent changes like commits, tags, or uploads were made."
fi

exit 0
