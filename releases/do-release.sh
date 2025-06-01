#!/usr/bin/env bash
#
# Main Release Orchestrator Script
# Purpose: Automates the entire release process for a Lua project,
#          including version management, rockspec generation, building,
#          Git tagging/committing, and publishing to LuaRocks.
#
# Execution Flow:
#   1. Defines key paths. Calls read-pkg-name.sh to get PKG_NAME from spec.template and exports it.
#   2. Parses command-line arguments for release options (including --upload-rock).
#   3. Calls manage-version.sh (which reads/writes version in spec.template)
#      to determine/set the release version. FINAL_VERSION is exported.
#   4. (Optional) Pre-flight check on LuaRocks if the version for PKG_NAME already exists.
#   5. Calls gen-rockspecs.sh to generate the rockspec file from spec.template
#      (which now has the final version and correct package name).
#   6. Calls build-rocks.sh to pack the generated rockspec into a .rock file.
#   7. Calls commit-and-tag-release.sh to commit changes (including spec.template),
#      create/push Git tag.
#   8. Calls publish-to-luarocks.sh to upload either the .rockspec or the .rock file to LuaRocks,
#      depending on the --upload-rock flag.
#   9. (Optional) Verifies the published package on LuaRocks (based on rockspec presence).
#
# Scripts Called (from ./scripts/ relative to this file's location):
#   - read-pkg-name.sh: Reads package name from spec.template.
#   - manage-version.sh: Handles version determination using spec.template.
#   - gen-rockspecs.sh: Generates the rockspec file.
#   - build-rocks.sh: Packs the rockspec.
#   - commit-and-tag-release.sh: Handles Git commit and tag.
#   - publish-to-luarocks.sh: Handles LuaRocks upload.
#
# Command-line Options:
#   --dry-run                         : Simulate the release. NOTE: manage-version.sh will still modify
#                                       spec.template if a version bump occurs, even in dry-run mode for do-release.
#   --use-version-file              : Use the version string directly from spec.template without prompting.
#   --bump <patch|minor|major>      : Automatically bump the version in spec.template by the specified type.
#   --upload-rock                   : If set, uploads the packed .rock file instead of the .rockspec file.
#                                       Default is to upload the .rockspec file.
#
# Environment Variables Set/Used:
#   - PKG_NAME (string)               : The base name of the package. Sourced from spec.template. Exported.
#   - PROJECT_ROOT_ABS (path)         : Absolute path to the project's root directory. Exported.
#   - SCRIPTS_DIR (path)              : Absolute path to the ./scripts/ directory. Exported.
#   - SPEC_TEMPLATE_ABS (path)        : Absolute path to the releases/spec.template file. Exported.
#   - FINAL_VERSION (string)          : The determined semantic version string (e.g., "0.9.0"). Exported.
#
# Current Working Directory (CWD) Convention:
#   This script changes the CWD to PROJECT_ROOT_ABS. Sub-scripts operate with this CWD.
#
set -e

# --- Path and Variable Definitions ---
RELEASES_ROOT=$(dirname "$(readlink -f "$0")") # Absolute path to releases/
export SCRIPTS_DIR="$RELEASES_ROOT/scripts"
export PROJECT_ROOT_ABS=$(readlink -f "$RELEASES_ROOT/..") # Absolute path to the project root
export SPEC_TEMPLATE_ABS="$RELEASES_ROOT/spec.template"
# VERSION_FILE_ABS is no longer used.

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

# --- Determine and Export PKG_NAME from spec.template ---
print_status "Determining package name from $SPEC_TEMPLATE_ABS..."
TEMP_PKG_NAME=$("$SCRIPTS_DIR/read-pkg-name.sh" "$SPEC_TEMPLATE_ABS")
if [ -z "$TEMP_PKG_NAME" ]; then
    print_error "Failed to read package name from $SPEC_TEMPLATE_ABS using read-pkg-name.sh. Aborting."
fi
export PKG_NAME="$TEMP_PKG_NAME"
print_success "Using PKG_NAME: $PKG_NAME (from spec.template)"

# --- Argument Parsing ---
DRY_RUN_FLAG=""
VERSION_ACTION_ARG=""
BUMP_TYPE_ARG=""
UPLOAD_ROCK_FILE_FLAG=false # Default to uploading rockspec

while [[ "$#" -gt 0 ]]; do
    case $1 in
    --dry-run)
        DRY_RUN_FLAG="--dry-run"
        print_warning "DRY RUN MODE ENABLED (Note: spec.template may still be modified by version bumping)"
        shift
        ;;
    --use-version-file)
        if [ -n "$VERSION_ACTION_ARG" ]; then print_error "Error: --use-version-file and --bump cannot be used together."; fi
        VERSION_ACTION_ARG="--use-current"
        print_status "Using version from $SPEC_TEMPLATE_ABS directly."
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
    --upload-rock)
        UPLOAD_ROCK_FILE_FLAG=true
        print_status "Will upload the packed .rock file instead of the .rockspec."
        shift
        ;;
    *)
        print_error "Unknown option: $1"
        ;;
    esac
done

# --- Step 1: Manage Version (from spec.template) ---
print_status "Step 1: Managing version (from $SPEC_TEMPLATE_ABS)..."
# manage-version.sh now needs SPEC_TEMPLATE_ABS and SCRIPTS_DIR.
export FINAL_VERSION=$("$SCRIPTS_DIR/manage-version.sh" "$SPEC_TEMPLATE_ABS" "$SCRIPTS_DIR" $VERSION_ACTION_ARG $BUMP_TYPE_ARG)
if [ -z "$FINAL_VERSION" ]; then print_error "Failed to determine final version."; fi
print_success "Version decided: $FINAL_VERSION for $PKG_NAME (spec.template updated if changed)"
echo

# --- Pre-flight Check: Verify Version Availability on LuaRocks (if not dry run) ---
if [ -z "$DRY_RUN_FLAG" ]; then
    print_status "Pre-flight Check: Verifying if version $FINAL_VERSION for '$PKG_NAME' is already on LuaRocks..."
    if luarocks search "$PKG_NAME" "$FINAL_VERSION" | grep -q "${FINAL_VERSION}-1 (rockspec)"; then
        print_error "Error: Version ${PKG_NAME} ${FINAL_VERSION}-1 is already published. Choose a different version."
    else
        print_success "Version ${PKG_NAME} $FINAL_VERSION appears to be available on LuaRocks."
    fi
    echo
fi

# --- Step 2: Generate Rockspecs ---
print_status "Step 2: Generating rockspec for $PKG_NAME version $FINAL_VERSION..."
# gen-rockspecs.sh uses exported env vars including SPEC_TEMPLATE_ABS (already updated by manage-version.sh)
GENERATED_ROCKSPECS_OUTPUT=$("$SCRIPTS_DIR/gen-rockspecs.sh")
if [ -z "$GENERATED_ROCKSPECS_OUTPUT" ]; then print_error "Failed to generate rockspec."; fi
mapfile -t GENERATED_ROCKSPEC_FILES < <(echo "$GENERATED_ROCKSPECS_OUTPUT")

print_success "Rockspec generated:"
for spec_file in "${GENERATED_ROCKSPEC_FILES[@]}"; do print_status "  - $spec_file"; done
echo

# --- Step 3: Build (Pack) Rocks ---
print_status "Step 3: Building (packing) rock..."
# build-rocks.sh operates on filenames (relative to CWD which is PROJECT_ROOT_ABS)
PACKED_ROCK_FILES_OUTPUT=$("$SCRIPTS_DIR/build-rocks.sh" "${GENERATED_ROCKSPEC_FILES[@]}")
if [ -z "$PACKED_ROCK_FILES_OUTPUT" ]; then print_error "Failed to build/pack rock."; fi
mapfile -t PACKED_ROCK_FILES < <(echo "$PACKED_ROCK_FILES_OUTPUT")
print_success "Rock packed:"
for rock_file in "${PACKED_ROCK_FILES[@]}"; do print_status "  - $rock_file (and any other variants)"; done
echo

# --- Step 4: Commit & Tag Release ---
print_status "Step 4: Committing and tagging release for $PKG_NAME v$FINAL_VERSION..."
# Pass SPEC_TEMPLATE_ABS (relative path from project root) to be committed along with generated rockspecs
SPEC_TEMPLATE_COMMIT_PATH="$(basename "$RELEASES_ROOT")/$(basename "$SPEC_TEMPLATE_ABS")" # e.g. releases/spec.template

ARGS_FOR_COMMIT=()
if [ -n "$DRY_RUN_FLAG" ]; then
    ARGS_FOR_COMMIT+=("$DRY_RUN_FLAG")
fi
ARGS_FOR_COMMIT+=("$SPEC_TEMPLATE_COMMIT_PATH")
ARGS_FOR_COMMIT+=("${GENERATED_ROCKSPEC_FILES[@]}")

"$SCRIPTS_DIR/commit-and-tag-release.sh" "${ARGS_FOR_COMMIT[@]}"
print_success "Release committed and tagged (or would be in dry run)."
echo

# --- Step 5: Publish to LuaRocks ---
print_status "Step 5: Publishing to LuaRocks..."
FILES_TO_PUBLISH=()
if [ "$UPLOAD_ROCK_FILE_FLAG" = true ]; then
    print_status "Uploading .rock file(s): ${PACKED_ROCK_FILES[*]}"
    FILES_TO_PUBLISH=("${PACKED_ROCK_FILES[@]}")
else
    print_status "Uploading .rockspec file(s): ${GENERATED_ROCKSPEC_FILES[*]}"
    FILES_TO_PUBLISH=("${GENERATED_ROCKSPEC_FILES[@]}")
fi

ARGS_FOR_PUBLISH=()
if [ -n "$DRY_RUN_FLAG" ]; then
    ARGS_FOR_PUBLISH+=("$DRY_RUN_FLAG")
fi
ARGS_FOR_PUBLISH+=("${FILES_TO_PUBLISH[@]}")

if [ ${#FILES_TO_PUBLISH[@]} -eq 0 ]; then
    print_error "No files determined for publishing. This shouldn't happen."
fi

"$SCRIPTS_DIR/publish-to-luarocks.sh" "${ARGS_FOR_PUBLISH[@]}"
print_success "Publish process to LuaRocks completed (or would be in dry run)."
echo

# --- Step 6: Verify on LuaRocks (if not dry run) ---
if [ -z "$DRY_RUN_FLAG" ]; then
    print_status "Step 6: Verifying package on LuaRocks..."
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
    if [ "$ALL_VERIFIED" = true ]; then print_success "Published package verified on LuaRocks."; else print_warning "Package could not be verified. Please check manually."; fi
    echo
fi

print_success "--------------------------------------------------"
print_success "RELEASE PROCESS COMPLETED SUCCESSFULLY for $PKG_NAME v$FINAL_VERSION!"
print_success "--------------------------------------------------"

if [ "$DRY_RUN_FLAG" = "--dry-run" ]; then print_warning "Remember, this was a DRY RUN."; fi
exit 0
