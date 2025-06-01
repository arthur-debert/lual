#!/usr/bin/env bash
#
# Main Release Orchestrator Script
# Purpose: Automates the entire release process for a Lua project,
#          including version management, rockspec generation, building,
#          Git tagging/committing, and publishing to LuaRocks.
#
# Execution Flow (Two Modes):
#   A) Template-based (default):
#     1. PKG_NAME read from spec.template.
#     2. manage-version.sh reads/bumps version in spec.template. FINAL_VERSION determined.
#     3. Pre-flight check for PKG_NAME + FINAL_VERSION on LuaRocks.
#     4. gen-rockspecs.sh generates <PKG_NAME>-<FINAL_VERSION>-1.rockspec from spec.template.
#     5. build-rocks.sh packs the generated rockspec.
#     6. commit-and-tag-release.sh commits spec.template and the generated rockspec.
#     7. publish-to-luarocks.sh uploads .rockspec or .rock file.
#     8. Verification on LuaRocks.
#   B) User-provided Rockspec File (if a .rockspec file is passed as an argument):
#     1. PKG_NAME and FINAL_VERSION read directly from the provided .rockspec file.
#        (manage-version.sh and version bumping are SKIPPED).
#     2. Pre-flight check for PKG_NAME + FINAL_VERSION on LuaRocks.
#     3. The provided .rockspec IS the file to be processed (gen-rockspecs.sh SKIPPED).
#     4. build-rocks.sh packs the provided .rockspec.
#     5. commit-and-tag-release.sh commits ONLY the provided .rockspec file.
#     6. publish-to-luarocks.sh uploads .rockspec or .rock file.
#     7. Verification on LuaRocks.
#
# Scripts Called (from ./scripts/ relative to this file's location):
#   - read-pkg-name.sh, read-version-from-spec.sh, manage-version.sh,
#   - gen-rockspecs.sh, build-rocks.sh, commit-and-tag-release.sh, publish-to-luarocks.sh
#
# Command-line Options:
#   [path/to/your.rockspec]       : Optional. If provided, uses this rockspec directly.
#   --dry-run                         : Simulate. NOTE: If not providing a rockspec, manage-version.sh
#                                       still modifies spec.template for bumps.
#   --use-version-file              : (Template mode only) Use version in spec.template without prompt.
#   --bump <patch|minor|major>      : (Template mode only) Bump version in spec.template.
#   --upload-rock                   : Upload packed .rock file instead of .rockspec.
#
# Environment Variables Set/Used:
#   - PKG_NAME, PROJECT_ROOT_ABS, SCRIPTS_DIR, SPEC_TEMPLATE_ABS, FINAL_VERSION (all exported)
#
set -e

# --- Path and Variable Definitions ---
RELEASES_ROOT=$(dirname "$(readlink -f "$0")") # Absolute path to releases/
export SCRIPTS_DIR="$RELEASES_ROOT/scripts"
export PROJECT_ROOT_ABS=$(readlink -f "$RELEASES_ROOT/..") # Absolute path to the project root
export SPEC_TEMPLATE_ABS="$RELEASES_ROOT/spec.template"    # Default master spec

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

# --- Argument Parsing for flags and optional rockspec file ---
DRY_RUN_FLAG=""
VERSION_ACTION_ARG=""
BUMP_TYPE_ARG=""
UPLOAD_ROCK_FILE_FLAG=false
USER_PROVIDED_ROCKSPEC=""

NEW_ARGS=()
for arg in "$@"; do
    if [[ -f "$arg" && "$arg" == *.rockspec && -z "$USER_PROVIDED_ROCKSPEC" ]]; then
        USER_PROVIDED_ROCKSPEC=$(readlink -f "$arg") # Get absolute path
        print_status "User provided rockspec file: $USER_PROVIDED_ROCKSPEC"
    else
        NEW_ARGS+=("$arg")
    fi
done
set -- "${NEW_ARGS[@]}" # Repopulate positional parameters without the rockspec file

while [[ "$#" -gt 0 ]]; do
    case $1 in
    --dry-run)
        DRY_RUN_FLAG="--dry-run"
        print_warning "DRY RUN MODE"
        shift
        ;;
    --use-version-file)
        if [ -n "$USER_PROVIDED_ROCKSPEC" ]; then print_error "--use-version-file cannot be used when a rockspec file is provided."; fi
        if [ -n "$VERSION_ACTION_ARG" ]; then print_error "--use-version-file and --bump cannot be used together."; fi
        VERSION_ACTION_ARG="--use-current"
        print_status "Using version from spec.template."
        shift
        ;;
    --bump)
        if [ -n "$USER_PROVIDED_ROCKSPEC" ]; then print_error "--bump cannot be used when a rockspec file is provided."; fi
        if [ -n "$VERSION_ACTION_ARG" ]; then print_error "--use-version-file and --bump cannot be used together."; fi
        if [[ -z "$2" ]] || [[ ! "$2" =~ ^(patch|minor|major)$ ]]; then print_error "--bump requires type (patch|minor|major)."; fi
        VERSION_ACTION_ARG="--bump-type"
        BUMP_TYPE_ARG="$2"
        print_status "Will bump by: $BUMP_TYPE_ARG"
        shift
        shift
        ;;
    --upload-rock)
        UPLOAD_ROCK_FILE_FLAG=true
        print_status "Will upload .rock file."
        shift
        ;;
    *) print_error "Unknown option: $1" ;;
    esac
done

# --- Determine PKG_NAME and FINAL_VERSION ---
if [ -n "$USER_PROVIDED_ROCKSPEC" ]; then
    print_status "Reading package name and version from provided rockspec: $USER_PROVIDED_ROCKSPEC"
    export PKG_NAME=$("$SCRIPTS_DIR/read-pkg-name.sh" "$USER_PROVIDED_ROCKSPEC")
    export FINAL_VERSION=$("$SCRIPTS_DIR/read-version-from-spec.sh" "$USER_PROVIDED_ROCKSPEC")
    if [ -z "$PKG_NAME" ] || [ -z "$FINAL_VERSION" ]; then print_error "Failed to read package/version from $USER_PROVIDED_ROCKSPEC."; fi
    print_success "Using PKG_NAME: $PKG_NAME, Version: $FINAL_VERSION (from provided rockspec)"
    GENERATED_ROCKSPEC_FILES=("$(basename "$USER_PROVIDED_ROCKSPEC")") # Relative path for build/publish
    # For commit, use path relative to project root
    if [[ "$USER_PROVIDED_ROCKSPEC" == "$PROJECT_ROOT_ABS"* ]]; then
        SPEC_TO_COMMIT_PATH="${USER_PROVIDED_ROCKSPEC#$PROJECT_ROOT_ABS/}"
    else
        SPEC_TO_COMMIT_PATH="$USER_PROVIDED_ROCKSPEC" # Should be an error or handled if not in project
        print_warning "Provided rockspec $USER_PROVIDED_ROCKSPEC is outside project root. Committing absolute path."
    fi
else
    print_status "Determining package name from default template: $SPEC_TEMPLATE_ABS..."
    export PKG_NAME=$("$SCRIPTS_DIR/read-pkg-name.sh" "$SPEC_TEMPLATE_ABS")
    if [ -z "$PKG_NAME" ]; then print_error "Failed to read PKG_NAME from $SPEC_TEMPLATE_ABS."; fi
    print_success "Using PKG_NAME: $PKG_NAME (from spec.template)"

    print_status "Step 1: Managing version (from $SPEC_TEMPLATE_ABS)..."
    export FINAL_VERSION=$("$SCRIPTS_DIR/manage-version.sh" "$SPEC_TEMPLATE_ABS" "$SCRIPTS_DIR" $VERSION_ACTION_ARG $BUMP_TYPE_ARG)
    if [ -z "$FINAL_VERSION" ]; then print_error "Failed to determine final version."; fi
    print_success "Version decided: $FINAL_VERSION for $PKG_NAME (spec.template updated if changed)"

    print_status "Step 2: Generating final rockspec for $PKG_NAME version $FINAL_VERSION..."
    GENERATED_ROCKSPECS_OUTPUT=$("$SCRIPTS_DIR/gen-rockspecs.sh")
    if [ -z "$GENERATED_ROCKSPECS_OUTPUT" ]; then print_error "Failed to generate rockspec."; fi
    mapfile -t GENERATED_ROCKSPEC_FILES < <(echo "$GENERATED_ROCKSPECS_OUTPUT")
    print_success "Rockspec generated: ${GENERATED_ROCKSPEC_FILES[*]}"
    SPEC_TO_COMMIT_PATH="$(basename "$RELEASES_ROOT")/$(basename "$SPEC_TEMPLATE_ABS")" # commit spec.template
fi
echo

# --- Pre-flight Check ---
if [ -z "$DRY_RUN_FLAG" ]; then
    print_status "Pre-flight Check: Verifying if '$PKG_NAME' v$FINAL_VERSION is on LuaRocks..."
    if luarocks search "$PKG_NAME" "$FINAL_VERSION" | grep -q "${FINAL_VERSION}-1 (rockspec)"; then
        print_error "Version ${PKG_NAME} ${FINAL_VERSION}-1 already published."
    else
        print_success "Version ${PKG_NAME} $FINAL_VERSION appears available."
    fi
    echo
fi

# --- Step 3 (or 2b if rockspec provided): Build/Pack Rock ---
print_status "Building (packing) rock from ${GENERATED_ROCKSPEC_FILES[*]}..."
PACKED_ROCK_FILES_OUTPUT=$("$SCRIPTS_DIR/build-rocks.sh" "${GENERATED_ROCKSPEC_FILES[@]}")
if [ -z "$PACKED_ROCK_FILES_OUTPUT" ]; then print_error "Failed to build/pack rock."; fi
mapfile -t PACKED_ROCK_FILES < <(echo "$PACKED_ROCK_FILES_OUTPUT")
print_success "Rock packed: ${PACKED_ROCK_FILES[*]}"
echo

# --- Step 4: Commit & Tag Release ---
print_status "Committing and tagging for $PKG_NAME v$FINAL_VERSION..."
ARGS_FOR_COMMIT=()
if [ -n "$DRY_RUN_FLAG" ]; then ARGS_FOR_COMMIT+=("$DRY_RUN_FLAG"); fi
ARGS_FOR_COMMIT+=("$SPEC_TO_COMMIT_PATH") # spec.template or user-provided spec
# If in template mode, also commit the generated rockspec. If user-provided, it's already SPEC_TO_COMMIT_PATH.
if [ -z "$USER_PROVIDED_ROCKSPEC" ]; then
    ARGS_FOR_COMMIT+=("${GENERATED_ROCKSPEC_FILES[@]}")
fi
"$SCRIPTS_DIR/commit-and-tag-release.sh" "${ARGS_FOR_COMMIT[@]}"
print_success "Committed and tagged."
echo

# --- Step 5: Publish to LuaRocks ---
print_status "Publishing to LuaRocks..."
FILES_TO_PUBLISH=()
if [ "$UPLOAD_ROCK_FILE_FLAG" = true ]; then
    print_status "Uploading .rock file(s): ${PACKED_ROCK_FILES[*]}"
    FILES_TO_PUBLISH=("${PACKED_ROCK_FILES[@]}")
else
    print_status "Uploading .rockspec file(s): ${GENERATED_ROCKSPEC_FILES[*]}"
    FILES_TO_PUBLISH=("${GENERATED_ROCKSPEC_FILES[@]}")
fi
ARGS_FOR_PUBLISH=()
if [ -n "$DRY_RUN_FLAG" ]; then ARGS_FOR_PUBLISH+=("$DRY_RUN_FLAG"); fi
ARGS_FOR_PUBLISH+=("${FILES_TO_PUBLISH[@]}")
if [ ${#FILES_TO_PUBLISH[@]} -eq 0 ]; then print_error "No files to publish."; fi
"$SCRIPTS_DIR/publish-to-luarocks.sh" "${ARGS_FOR_PUBLISH[@]}"
print_success "Publish process completed."
echo

# --- Step 6: Verify on LuaRocks ---
if [ -z "$DRY_RUN_FLAG" ]; then
    print_status "Verifying package on LuaRocks..."
    VERIFY_SPEC_FILE="${GENERATED_ROCKSPEC_FILES[0]}" # Use first (only) element
    PKG_NAME_FROM_FILE=$(basename "$VERIFY_SPEC_FILE" | sed -E "s/-${FINAL_VERSION}-[0-9]+\.rockspec//")
    if [ -n "$PKG_NAME_FROM_FILE" ]; then
        print_status "Searching for ${PKG_NAME_FROM_FILE} v$FINAL_VERSION on LuaRocks..."
        if luarocks search "$PKG_NAME_FROM_FILE" "$FINAL_VERSION" | grep -q "${FINAL_VERSION}-1 (rockspec)"; then
            print_success "Found ${PKG_NAME_FROM_FILE} ${FINAL_VERSION} on LuaRocks."
        else
            print_warning "Could not verify ${PKG_NAME_FROM_FILE} ${FINAL_VERSION} on LuaRocks. Check manually."
        fi
    else
        print_warning "Could not parse PKG_NAME from $VERIFY_SPEC_FILE to verify."
    fi
    echo
fi

print_success "--------------------------------------------------"
print_success "RELEASE PROCESS COMPLETED SUCCESSFULLY for $PKG_NAME v$FINAL_VERSION!"
print_success "--------------------------------------------------"
if [ "$DRY_RUN_FLAG" = "--dry-run" ]; then print_warning "Remember, this was a DRY RUN."; fi
exit 0
