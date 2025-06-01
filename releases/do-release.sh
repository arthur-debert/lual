#!/usr/bin/env bash
#
# Main Release Orchestrator Script
# Purpose: Automates the entire release process for a Lua project,
#          including version management, rockspec generation, building,
#          Git tagging/committing, and publishing to LuaRocks.
#
# Execution Flow:
#   1. Defines and exports key paths and package name (PKG_NAME).
#   2. Parses command-line arguments for release options.
#   3. Calls manage-version.sh to determine/set the release version.
#   4. (Optional) Pre-flight check on LuaRocks if the version already exists.
#   5. Calls gen-rockspecs.sh to generate rockspec files from templates.
#   6. Calls build-rocks.sh to pack the generated rockspecs into .rock files.
#   7. Calls commit-and-tag-release.sh to commit changes, create/push Git tag.
#   8. Calls publish-to-luarocks.sh to upload rockspecs to LuaRocks.
#   9. (Optional) Verifies the published packages on LuaRocks.
#
# Scripts Called (from ./scripts/ relative to this file's location):
#   - manage-version.sh: Handles version determination (interactive or via flags).
#   - gen-rockspecs.sh: Generates rockspec files.
#   - build-rocks.sh: Packs rockspecs.
#   - commit-and-tag-release.sh: Handles Git commit and tag.
#   - publish-to-luarocks.sh: Handles LuaRocks upload.
#
# Command-line Options:
#   --with-extras                     : Include the extras package in the release.
#   --dry-run                         : Simulate the release without making permanent changes (commits, tags, uploads).
#   --use-version-file              : Use the version string directly from releases/VERSION without prompting.
#   --bump <patch|minor|major>      : Automatically bump the version by the specified type without prompting.
#
# Environment Variables Set/Used:
#   - PKG_NAME (string)               : The base name of the package
#                                       Read from env, must be set
#   - PROJECT_ROOT_ABS (path)         : Absolute path to the project's root directory. Exported.
#   - SCRIPTS_DIR (path)              : Absolute path to the ./scripts/ directory. Exported.
#   - VERSION_FILE_ABS (path)         : Absolute path to the releases/VERSION file. Exported.
#   - SPEC_TEMPLATE_ABS (path)        : Absolute path to the releases/spec.template file. Exported.
#   - EXTRAS_TEMPLATE_ABS (path)      : Absolute path to the releases/extras.spec.template file. Exported.
#   - FINAL_VERSION (string)          : The determined version string for the release (e.g., "0.9.0"). Exported.
#
# Current Working Directory (CWD) Convention:
#   This script changes the CWD to PROJECT_ROOT_ABS. Sub-scripts are expected to operate
#   with this CWD, or use the absolute paths provided via exported variables.
#
set -e

# --- Path and Variable Definitions ---
RELEASES_ROOT=$(dirname "$(readlink -f "$0")") # Absolute path to releases/
export SCRIPTS_DIR="$RELEASES_ROOT/scripts"
export PROJECT_ROOT_ABS=$(readlink -f "$RELEASES_ROOT/..") # Absolute path to the project root
export VERSION_FILE_ABS="$RELEASES_ROOT/VERSION"
export SPEC_TEMPLATE_ABS="$RELEASES_ROOT/spec.template"
export EXTRAS_TEMPLATE_ABS="$RELEASES_ROOT/extras.spec.template"

cd "$PROJECT_ROOT_ABS" # Set current working directory to project root for all subsequent commands

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

# --- Environment Variable Check for PKG_NAME ---
if [ -z "$PKG_NAME" ]; then
    print_warning "PKG_NAME environment variable not set, aborting"
    exit 1
else
    export PKG_NAME # Ensure it's exported if already set
fi
print_status "Using PKG_NAME: $PKG_NAME"

# --- Argument Parsing ---
WITH_EXTRAS_FLAG=""
DRY_RUN_FLAG=""
VERSION_ACTION_ARG=""
BUMP_TYPE_ARG=""

while [[ "$#" -gt 0 ]]; do
    case $1 in
    --with-extras)
        WITH_EXTRAS_FLAG="--with-extras"
        print_status "Including ${PKG_NAME}extras in this release."
        shift
        ;;
    --dry-run)
        DRY_RUN_FLAG="--dry-run"
        print_warning "DRY RUN MODE ENABLED"
        shift
        ;;
    --use-version-file)
        if [ -n "$VERSION_ACTION_ARG" ]; then print_error "Error: --use-version-file and --bump cannot be used together."; fi
        VERSION_ACTION_ARG="--use-current"
        print_status "Using version from $VERSION_FILE_ABS directly."
        shift
        ;;
    --bump)
        if [ -n "$VERSION_ACTION_ARG" ]; then print_error "Error: --use-version-file and --bump cannot be used together."; fi
        if [[ -z "$2" ]] || [[ ! "$2" =~ ^(patch|minor|major)$ ]]; then print_error "Error: --bump requires a type (patch, minor, or major)."; fi
        VERSION_ACTION_ARG="--bump-type"
        BUMP_TYPE_ARG="$2"
        print_status "Will bump version by: $BUMP_TYPE_ARG"
        shift
        shift
        ;;
    *)
        print_error "Unknown option: $1"
        ;;
    esac
done

# --- Step 1: Manage Version ---
print_status "Step 1: Managing version..."
# manage-version.sh needs VERSION_FILE_ABS and SCRIPTS_DIR (for bump-version) passed explicitly for this stage
# It will output the chosen version string.
export FINAL_VERSION=$("$SCRIPTS_DIR/manage-version.sh" "$VERSION_FILE_ABS" "$SCRIPTS_DIR" $VERSION_ACTION_ARG $BUMP_TYPE_ARG)
if [ -z "$FINAL_VERSION" ]; then print_error "Failed to determine final version."; fi
print_success "Version decided: $FINAL_VERSION for $PKG_NAME"
echo

# --- Pre-flight Check: Verify Version Availability on LuaRocks (if not dry run) ---
if [ -z "$DRY_RUN_FLAG" ]; then
    print_status "Pre-flight Check: Verifying if version $FINAL_VERSION for '$PKG_NAME' is already on LuaRocks..."
    if luarocks search "$PKG_NAME" "$FINAL_VERSION" | grep -q "${FINAL_VERSION}-1 (rockspec)"; then
        print_error "Error: Version ${PKG_NAME} ${FINAL_VERSION}-1 is already published. Choose a different version."
    else
        print_success "Version ${PKG_NAME} $FINAL_VERSION appears to be available on LuaRocks."
    fi
    if [ "$WITH_EXTRAS_FLAG" = "--with-extras" ]; then
        EXTRAS_PKG_NAME="${PKG_NAME}extras"
        print_status "Pre-flight Check: Verifying if version $FINAL_VERSION for '$EXTRAS_PKG_NAME' is already on LuaRocks..."
        if luarocks search "$EXTRAS_PKG_NAME" "$FINAL_VERSION" | grep -q "${FINAL_VERSION}-1 (rockspec)"; then
            print_error "Error: Version ${EXTRAS_PKG_NAME} ${FINAL_VERSION}-1 is already published. Choose a different version."
        else
            print_success "Version ${EXTRAS_PKG_NAME} $FINAL_VERSION appears to be available on LuaRocks."
        fi
    fi
    echo
fi

# --- Step 2: Generate Rockspecs ---
print_status "Step 2: Generating rockspecs for $PKG_NAME version $FINAL_VERSION..."
# gen-rockspecs.sh will use exported env vars: PROJECT_ROOT_ABS, PKG_NAME, FINAL_VERSION, SPEC_TEMPLATE_ABS, EXTRAS_TEMPLATE_ABS
GENERATED_ROCKSPECS_OUTPUT=$("$SCRIPTS_DIR/gen-rockspecs.sh" "$WITH_EXTRAS_FLAG") # Only needs with_extras flag now
if [ -z "$GENERATED_ROCKSPECS_OUTPUT" ]; then print_error "Failed to generate rockspecs."; fi
mapfile -t GENERATED_ROCKSPEC_FILES < <(echo "$GENERATED_ROCKSPECS_OUTPUT")

print_success "Rockspecs generated:"
for spec_file in "${GENERATED_ROCKSPEC_FILES[@]}"; do print_status "  - $spec_file"; done
echo

# --- Step 3: Build (Pack) Rocks ---
print_status "Step 3: Building (packing) rocks..."
# build-rocks.sh operates on filenames (relative to CWD which is PROJECT_ROOT_ABS)
PACKED_ROCK_FILES_OUTPUT=$("$SCRIPTS_DIR/build-rocks.sh" "${GENERATED_ROCKSPEC_FILES[@]}")
if [ -z "$PACKED_ROCK_FILES_OUTPUT" ]; then print_error "Failed to build/pack rocks."; fi
mapfile -t PACKED_ROCK_FILES < <(echo "$PACKED_ROCK_FILES_OUTPUT")
print_success "Rocks packed:"
for rock_file in "${PACKED_ROCK_FILES[@]}"; do print_status "  - $rock_file (and any other variants)"; done
echo

# --- Step 4: Commit & Tag Release ---
print_status "Step 4: Committing and tagging release for $PKG_NAME v$FINAL_VERSION..."
# commit-and-tag-release.sh uses exported FINAL_VERSION and operates on filenames relative to CWD.
"$SCRIPTS_DIR/commit-and-tag-release.sh" "$DRY_RUN_FLAG" "${GENERATED_ROCKSPEC_FILES[@]}"
print_success "Release committed and tagged (or would be in dry run)."
echo

# --- Step 5: Publish to LuaRocks ---
print_status "Step 5: Publishing to LuaRocks..."
# publish-to-luarocks.sh operates on filenames relative to CWD.
"$SCRIPTS_DIR/publish-to-luarocks.sh" "$DRY_RUN_FLAG" "${GENERATED_ROCKSPEC_FILES[@]}"
print_success "Publish process to LuaRocks completed (or would be in dry run)."
echo

# --- Step 6: Verify on LuaRocks (if not dry run) ---
if [ -z "$DRY_RUN_FLAG" ]; then
    print_status "Step 6: Verifying packages on LuaRocks..."
    ALL_VERIFIED=true
    for spec_file in "${GENERATED_ROCKSPEC_FILES[@]}"; do
        PKG_NAME_FROM_FILE=$(basename "$spec_file" | sed -E "s/-${FINAL_VERSION}-[0-9]+\.rockspec//")
        if [ -n "$PKG_NAME_FROM_FILE" ]; then
            print_status "Searching for ${PKG_NAME_FROM_FILE} version ${FINAL_VERSION} on LuaRocks..."
            if luarocks search "$PKG_NAME_FROM_FILE" "$FINAL_VERSION" | grep -q "${FINAL_VERSION}-1 (rockspec)"; then
                print_success "  Successfully found ${PKG_NAME_FROM_FILE} ${FINAL_VERSION} on LuaRocks."
            else
                print_warning "  Could not verify ${PKG_NAME_FROM_FILE} ${FINAL_VERSION} on LuaRocks. Check manually."
                ALL_VERIFIED=false
            fi
        else
            print_warning "Could not parse package name from ${spec_file} to verify."
            ALL_VERIFIED=false
        fi
    done
    if [ "$ALL_VERIFIED" = true ]; then print_success "All published packages verified on LuaRocks."; else print_warning "Some packages could not be verified. Please check manually."; fi
    echo
fi

print_success "--------------------------------------------------"
print_success "RELEASE PROCESS COMPLETED SUCCESSFULLY for $PKG_NAME v$FINAL_VERSION!"
print_success "--------------------------------------------------"

if [ "$DRY_RUN_FLAG" = "--dry-run" ]; then print_warning "Remember, this was a DRY RUN."; fi
exit 0
