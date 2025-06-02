#!/usr/bin/env bash
#
# Main Release Orchestrator Script
# Purpose: Automates the entire release process for a Lua project.
#
# Execution Flow:
#   1. Defines paths. PKG_NAME is from environment (must be set).
#   2. Determines METADATA_SOURCE_FILE (user-provided .rockspec or default spec.template).
#   3. Reads INITIAL_VERSION from METADATA_SOURCE_FILE using read-version-from-spec.sh.
#   4. Parses command-line arguments for release options.
#   5. Calls manage-version.sh (now a pure calculator) with INITIAL_VERSION to get FINAL_VERSION.
#   6. IF template mode AND version changed: update-spec-version.sh updates spec.template with FINAL_VERSION.
#   7. Pre-flight check for PKG_NAME + FINAL_VERSION on LuaRocks.
#   8. gen-rockspecs.sh generates <PKG_NAME>-<FINAL_VERSION>-1.rockspec using METADATA_SOURCE_FILE as base.
#   9. build-rocks.sh packs the generated rockspec.
#  10. commit-and-tag-release.sh commits relevant file(s) (spec.template if changed, generated rockspec).
#  11. publish-to-luarocks.sh uploads .rockspec or .rock file.
#  12. Verification on LuaRocks.
#
# Scripts Called (from ./scripts/):
#   read-version-from-spec.sh, manage-version.sh, update-spec-version.sh (new),
#   gen-rockspecs.sh, build-rocks.sh, commit-and-tag-release.sh, publish-to-luarocks.sh
#
# Command-line Options:
#   [path/to/your.rockspec]       : Optional. If provided, version is read from this file. Bumping applies to this initial version.
#                                   The original file is NOT modified; a new canonical rockspec is generated from it.
#   --dry-run                         : Simulate. NOTE: If in template mode and version bumped, spec.template IS updated.
#   --use-version-file              : Use version in source spec file without prompt for bump.
#   --bump <patch|minor|major>      : Bump version from source spec file.
#   --upload-rock                   : Upload packed .rock file instead of .rockspec.
#   --gh-release <true|false>       : Create a GitHub release (default: true).
#
# Environment Variables Set/Used:
#   - PKG_NAME (string)               : Base package name. MUST BE SET IN ENVIRONMENT. Exported.
#   - PROJECT_ROOT_ABS (path)         : Absolute path to project root. Exported.
#   - SCRIPTS_DIR (path)              : Absolute path to ./scripts/ directory. Exported.
#   - DEFAULT_SPEC_TEMPLATE_ABS (path): Path to releases/spec.template. (Used by gen-rockspecs.sh if no user spec)
#   - FINAL_VERSION (string)          : Determined semantic version (e.g., "0.9.0"). Exported.
#
set -e

# --- Path and Variable Definitions ---
RELEASES_ROOT=$(dirname "$(readlink -f "$0")")
export SCRIPTS_DIR="$RELEASES_ROOT/scripts"
export PROJECT_ROOT_ABS=$(readlink -f "$RELEASES_ROOT/..")
export DEFAULT_SPEC_TEMPLATE_ABS="$RELEASES_ROOT/spec.template" # Renamed from SPEC_TEMPLATE_ABS for clarity

cd "$PROJECT_ROOT_ABS"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
print_status() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# --- PKG_NAME must be set in environment ---
if [ -z "$PKG_NAME" ]; then print_error "PKG_NAME environment variable not set. This is required."; fi
export PKG_NAME
print_status "Using PKG_NAME: $PKG_NAME (from environment)"

# --- Argument Parsing for flags and optional rockspec file ---
DRY_RUN_FLAG=""
VERSION_ACTION_ARG=""
BUMP_TYPE_ARG=""
UPLOAD_ROCK_FILE_FLAG=false
USER_PROVIDED_ROCKSPEC_PATH=""
CREATE_GH_RELEASE=true # Default to true

NEW_ARGS=()
for arg in "$@"; do
    if [[ -f "$arg" && "$arg" == *.rockspec && -z "$USER_PROVIDED_ROCKSPEC_PATH" ]]; then
        USER_PROVIDED_ROCKSPEC_PATH=$(readlink -f "$arg")
    else
        NEW_ARGS+=("$arg")
    fi
done
set -- "${NEW_ARGS[@]}"

while [[ "$#" -gt 0 ]]; do
    case $1 in
    --dry-run)
        DRY_RUN_FLAG="--dry-run"
        print_warning "DRY RUN MODE (Note: spec.template may still be modified if version is bumped)"
        shift
        ;;
    --use-version-file)
        if [ -n "$VERSION_ACTION_ARG" ]; then print_error "--use-version-file and --bump cannot be used together."; fi
        VERSION_ACTION_ARG="--use-current"
        print_status "Using version from source spec file."
        shift
        ;;
    --bump)
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
    --gh-release)
        if [[ -z "$2" ]] || ! [[ "$2" =~ ^(true|false)$ ]]; then print_error "--gh-release requires true or false."; fi
        if [ "$2" = "false" ]; then
            CREATE_GH_RELEASE=false
            print_status "GitHub release creation will be skipped."
        else
            CREATE_GH_RELEASE=true # Explicitly true, or if already default true
            print_status "Will attempt to create a GitHub release."
        fi
        shift # consume --gh-release
        shift # consume true/false
        ;;
    *) print_error "Unknown option: $1" ;;
    esac
done

# --- GH CLI Check (if GitHub release is enabled) ---
if [ "$CREATE_GH_RELEASE" = true ]; then
    if ! command -v gh &>/dev/null; then
        print_error "GitHub CLI 'gh' not found, but GitHub release creation is enabled. \\nPlease install 'gh' (see https://cli.github.com/) or disable GitHub releases with '--gh-release false'."
    else
        print_status "'gh' command found. GitHub release creation is active."
    fi
    echo # Newline for readability
fi

# --- Determine METADATA_SOURCE_FILE (for reading initial Pkg Name and Version) ---
METADATA_SOURCE_FILE_ABS=""
if [ -n "$USER_PROVIDED_ROCKSPEC_PATH" ]; then
    if [ ! -f "$USER_PROVIDED_ROCKSPEC_PATH" ]; then print_error "Provided rockspec file not found: $USER_PROVIDED_ROCKSPEC_PATH"; fi
    METADATA_SOURCE_FILE_ABS="$USER_PROVIDED_ROCKSPEC_PATH"
    print_status "Source for initial metadata: User-provided rockspec ($METADATA_SOURCE_FILE_ABS)"
else
    METADATA_SOURCE_FILE_ABS="$DEFAULT_SPEC_TEMPLATE_ABS"
    print_status "Source for initial metadata: Default spec template ($METADATA_SOURCE_FILE_ABS)"
fi

# PKG_NAME is from env. Read INITIAL_VERSION from METADATA_SOURCE_FILE_ABS.
print_status "Reading initial version from $METADATA_SOURCE_FILE_ABS..."
INITIAL_SEMANTIC_VERSION=$("$SCRIPTS_DIR/read-version-from-spec.sh" "$METADATA_SOURCE_FILE_ABS")
if [ -z "$INITIAL_SEMANTIC_VERSION" ]; then print_error "Failed to read initial version from $METADATA_SOURCE_FILE_ABS."; fi
print_status "Initial version read: $INITIAL_SEMANTIC_VERSION for package $PKG_NAME"

# --- Step 1: Calculate Final Version (using manage-version.sh as a pure calculator) ---
print_status "Step 1: Calculating final version..."
export FINAL_VERSION=$("$SCRIPTS_DIR/manage-version.sh" "$INITIAL_SEMANTIC_VERSION" "$SCRIPTS_DIR" $VERSION_ACTION_ARG $BUMP_TYPE_ARG)
if [ -z "$FINAL_VERSION" ]; then print_error "Failed to determine final version."; fi
print_success "Final version decided: $FINAL_VERSION for $PKG_NAME"

# --- Step 1b: Update spec.template if it was the source and version was bumped ---
# This ensures the template carries the next version for subsequent default runs.
# User-provided rockspecs are NOT modified.
SPEC_TEMPLATE_WAS_MODIFIED=false
if [ -z "$USER_PROVIDED_ROCKSPEC_PATH" ] && [ "$INITIAL_SEMANTIC_VERSION" != "$FINAL_VERSION" ]; then
    print_status "Updating version in default spec template ($DEFAULT_SPEC_TEMPLATE_ABS) to $FINAL_VERSION..."
    # update-spec-version.sh modifies the file in place.
    "$SCRIPTS_DIR/update-spec-version.sh" "$DEFAULT_SPEC_TEMPLATE_ABS" "$FINAL_VERSION"
    SPEC_TEMPLATE_WAS_MODIFIED=true
    print_success "Default spec template updated."
fi
echo

# Initialize files to be committed and file used for generation
declare -a GENERATED_ROCKSPEC_FILES=() # This will hold the single, final rockspec filename for build/publish
SPEC_TO_COMMIT_PRIMARY=""              # Primary file to commit (template or user-spec)
SPEC_TO_COMMIT_SECONDARY=""            # Secondary file to commit (generated spec, if template mode)
SOURCE_FOR_GENSPECS=""                 # The file gen-rockspecs.sh will copy from

if [ -n "$USER_PROVIDED_ROCKSPEC_PATH" ]; then
    # Mode: User-provided Rockspec File
    # The user-provided file (unmodified by version bump) is the source for gen-rockspecs.
    # The final generated rockspec will have the PKG_NAME (from env) and FINAL_VERSION.
    SOURCE_FOR_GENSPECS="$USER_PROVIDED_ROCKSPEC_PATH"
    # We commit the original user-provided rockspec (it was not modified).
    if [[ "$USER_PROVIDED_ROCKSPEC_PATH" == "$PROJECT_ROOT_ABS"* ]]; then
        SPEC_TO_COMMIT_PRIMARY="${USER_PROVIDED_ROCKSPEC_PATH#$PROJECT_ROOT_ABS/}"
    else
        SPEC_TO_COMMIT_PRIMARY="$USER_PROVIDED_ROCKSPEC_PATH"
    fi
else
    # Mode: Template-based
    # The default spec template (which was just updated if version bumped) is the source for gen-rockspecs.
    SOURCE_FOR_GENSPECS="$DEFAULT_SPEC_TEMPLATE_ABS"
    SPEC_TO_COMMIT_PRIMARY="$(basename "$RELEASES_ROOT")/$(basename "$DEFAULT_SPEC_TEMPLATE_ABS")" # e.g. releases/spec.template
fi

# --- Step 2: Generate Final Buildable Rockspec ---
# gen-rockspecs.sh copies SOURCE_FOR_GENSPECS and stamps PKG_NAME & FINAL_VERSION into the new file.
print_status "Step 2: Generating final buildable rockspec for $PKG_NAME version $FINAL_VERSION..."
GENERATED_ROCKSPECS_OUTPUT=$("$SCRIPTS_DIR/gen-rockspecs.sh" "$SOURCE_FOR_GENSPECS")
if [ -z "$GENERATED_ROCKSPECS_OUTPUT" ]; then print_error "Failed to generate final rockspec."; fi
mapfile -t GENERATED_ROCKSPEC_FILES < <(echo "$GENERATED_ROCKSPECS_OUTPUT") # Should be one file
print_success "Final rockspec for build/publish: ${GENERATED_ROCKSPEC_FILES[*]}"

# If template mode, the second file to commit is this newly generated rockspec.
# If user-provided spec mode, GENERATED_ROCKSPEC_FILES[0] IS the one to build/publish and also commit (if different from original user path due to naming convention)
# but SPEC_TO_COMMIT_PRIMARY already points to the original user spec path.
# This logic needs to be cleaner for what to commit if user spec is provided.
# For now: if template, commit template + generated. If user-spec, commit original user-spec + generated.
# This seems right if gen-rockspecs always makes a NEW file like <PKG_NAME>-<FINAL_VERSION>-1.rockspec
if [ -z "$USER_PROVIDED_ROCKSPEC_PATH" ]; then
    SPEC_TO_COMMIT_SECONDARY="${GENERATED_ROCKSPEC_FILES[0]}"
elif [ "$(basename "$USER_PROVIDED_ROCKSPEC_PATH")" != "${GENERATED_ROCKSPEC_FILES[0]}" ]; then
    # User provided a spec, and the generated spec has a different (canonical) name.
    # We should commit the generated one. The original user one is not modified or committed.
    SPEC_TO_COMMIT_PRIMARY="${GENERATED_ROCKSPEC_FILES[0]}" # Commit the canonical one.
    SPEC_TO_COMMIT_SECONDARY=""                             # No secondary in this case.
fi
echo

# --- Pre-flight Check ---
if [ -z "$DRY_RUN_FLAG" ]; then
    print_status "Pre-flight Check: Verifying if '$PKG_NAME' v$FINAL_VERSION is on LuaRocks..."
    # Suppress stderr of luarocks search (e.g. "falling back to wget")
    # Grep will get stdout. If luarocks search fails, set -e handles it.
    if (luarocks search "$PKG_NAME" "$FINAL_VERSION" 2>/dev/null) | grep -q -- "--rockspec-version=${FINAL_VERSION}-1"; then
        print_error "Version ${PKG_NAME} ${FINAL_VERSION}-1 already published."
    elif (luarocks search "$PKG_NAME" "$FINAL_VERSION" 2>/dev/null) | grep -q -- "${FINAL_VERSION}-1 (rockspec)"; then # Legacy check, some luarocks versions might show this
        print_error "Version ${PKG_NAME} ${FINAL_VERSION}-1 already published."
    elif (luarocks search "$PKG_NAME" "$FINAL_VERSION" 2>/dev/null) | grep -q -- "${PKG_NAME} ${FINAL_VERSION}"; then # Broader check for the package and version
        # This might indicate the version is published in some form, even if not an exact rockspec match string
        # For safety, consider this as potentially published, though it may need manual verification
        # Example: luarocks search lpeg -> lpeg 1.0.2-1 (installed)
        # Example: luarocks search lual 0.8.19 -> lual 0.8.19-1 (rockspec) ... but what if only 'lual 0.8.19' is listed by 'luarocks list'?
        # The original grep was for "${FINAL_VERSION}-1 (rockspec)" which is quite specific.
        # Let's stick to a more direct check if possible. The API returns rockspec files with specific version-revision.
        # The original grep was: grep -q "${FINAL_VERSION}-1 (rockspec)"
        # Updated to be more robust with various luarocks versions output:
        # Match lines like: <pkg_name> <version>-<revision> (rockspec|installed|...) or --rockspec-version=<version>-<revision>
        # We primarily care if a rockspec for this exact version-revision is findable.
        SEARCH_OUTPUT=$(luarocks search "$PKG_NAME" "$FINAL_VERSION" 2>/dev/null)
        if echo "$SEARCH_OUTPUT" | grep -Eq "(${PKG_NAME}[[:space:]]+${FINAL_VERSION}-1|--rockspec-version=${FINAL_VERSION}-1)"; then
            print_error "Version ${PKG_NAME} ${FINAL_VERSION}-1 appears to be already published or registered on LuaRocks."
        else
            print_success "Version ${PKG_NAME} $FINAL_VERSION appears available."
        fi
    else
        print_success "Version ${PKG_NAME} $FINAL_VERSION appears available."
    fi
    echo
fi

# --- Build/Pack Rock ---
print_status "Building (packing) rock from ${GENERATED_ROCKSPEC_FILES[*]}..."
PACKED_ROCK_FILES_OUTPUT=$("$SCRIPTS_DIR/build-rocks.sh" "${GENERATED_ROCKSPEC_FILES[@]}")
if [ -z "$PACKED_ROCK_FILES_OUTPUT" ]; then print_error "Failed to build/pack rock."; fi
mapfile -t PACKED_ROCK_FILES < <(echo "$PACKED_ROCK_FILES_OUTPUT")
print_success "Rock packed: ${PACKED_ROCK_FILES[*]}"
echo

# --- Commit & Tag Release ---
print_status "Committing and tagging for $PKG_NAME v$FINAL_VERSION..."
ARGS_FOR_COMMIT=()
if [ -n "$DRY_RUN_FLAG" ]; then ARGS_FOR_COMMIT+=("$DRY_RUN_FLAG"); fi
if [ -n "$SPEC_TO_COMMIT_PRIMARY" ]; then ARGS_FOR_COMMIT+=("$SPEC_TO_COMMIT_PRIMARY"); fi
if [ -n "$SPEC_TO_COMMIT_SECONDARY" ]; then ARGS_FOR_COMMIT+=("$SPEC_TO_COMMIT_SECONDARY"); fi

if [ ${#ARGS_FOR_COMMIT[@]} -eq 0 ] || ([ -n "$DRY_RUN_FLAG" ] && [ ${#ARGS_FOR_COMMIT[@]} -eq 1 ]); then
    print_warning "No files identified for commit (or only dry-run flag). Skipping commit step."
else
    "$SCRIPTS_DIR/commit-and-tag-release.sh" "${ARGS_FOR_COMMIT[@]}"
    print_success "Committed and tagged."
    echo
fi

# --- Publish to LuaRocks ---
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
if [ ${#FILES_TO_PUBLISH[@]} -eq 0 ] || ([ "${#ARGS_FOR_PUBLISH[@]}" -eq 1 ] && [ -n "$DRY_RUN_FLAG" ]); then
    print_error "No files determined for publishing (array is empty or only contains --dry-run)."
fi

# Capture the output of publish-to-luarocks.sh, which should be the URL if successful
PUBLISHED_LUAROCKS_URL=""
if [ -z "$DRY_RUN_FLAG" ]; then # Only attempt to capture URL if not a dry run
    # The actual publish script redirects its own info/errors to stderr.
    # Its stdout should only contain the URL if successful.
    PUBLISHED_LUAROCKS_URL=$("$SCRIPTS_DIR/publish-to-luarocks.sh" "${ARGS_FOR_PUBLISH[@]}")
    # Check if publish-to-luarocks.sh itself failed (it exits on error)
    if [ $? -ne 0 ] && [ -z "$PUBLISHED_LUAROCKS_URL" ]; then # If script failed and no URL was output
        # Error message already printed by publish-to-luarocks.sh, do-release.sh will exit due to set -e
        # but we can add a more general one here if needed, or just let set -e handle it.
        print_error "Publishing script failed. See messages above."
    fi
else
    # In dry run, publish-to-luarocks.sh is called with --dry-run and will only print to stderr.
    "$SCRIPTS_DIR/publish-to-luarocks.sh" "${ARGS_FOR_PUBLISH[@]}"
fi

print_success "Publish process completed."
echo

# --- Verify on LuaRocks ---
if [ -z "$DRY_RUN_FLAG" ]; then
    print_status "Verifying package on LuaRocks..."
    # PKG_NAME and FINAL_VERSION are from env/spec, should be reliable
    print_status "Searching for ${PKG_NAME} v$FINAL_VERSION on LuaRocks..."
    # Suppress stderr of luarocks search (e.g. "falling back to wget")
    SEARCH_OUTPUT_VERIFY=$(luarocks search "$PKG_NAME" "$FINAL_VERSION" 2>/dev/null)
    if echo "$SEARCH_OUTPUT_VERIFY" | grep -Eq "(${PKG_NAME}[[:space:]]+${FINAL_VERSION}-1|--rockspec-version=${FINAL_VERSION}-1)"; then
        print_success "Found ${PKG_NAME} ${FINAL_VERSION} on LuaRocks."
    else
        print_warning "Could not verify ${PKG_NAME} ${FINAL_VERSION} on LuaRocks. Check manually. Search output:\n$SEARCH_OUTPUT_VERIFY"
    fi
    echo
fi

# After LuaRocks publish, before cleanup
if [ "$CREATE_GH_RELEASE" = true ] && [ -z "$DRY_RUN_FLAG" ]; then
    print_status "Creating GitHub release for v$FINAL_VERSION..."
    # Determine assets to upload: typically the .src.rock and the .rockspec
    # PACKED_ROCK_FILES array contains the .src.rock file(s)
    # GENERATED_ROCKSPEC_FILES array contains the .rockspec file(s)
    # Assuming single primary package for now
    ASSETS_FOR_GH_RELEASE=()
    if [ ${#PACKED_ROCK_FILES[@]} -gt 0 ]; then
        ASSETS_FOR_GH_RELEASE+=("${PACKED_ROCK_FILES[0]}") # Add the .src.rock
    fi
    if [ ${#GENERATED_ROCKSPEC_FILES[@]} -gt 0 ]; then
        ASSETS_FOR_GH_RELEASE+=("${GENERATED_ROCKSPEC_FILES[0]}") # Add the .rockspec
    fi

    if [ ${#ASSETS_FOR_GH_RELEASE[@]} -gt 0 ]; then
        # Call the new script:
        # Need to pass: tag, and asset files
        # Tag is v$FINAL_VERSION
        GH_RELEASE_TAG="v${FINAL_VERSION}"
        "$SCRIPTS_DIR/create-gh-release.sh" "$GH_RELEASE_TAG" "${ASSETS_FOR_GH_RELEASE[@]}"
        # create-gh-release.sh should handle its own success/error messages
        # set -e will cause do-release.sh to exit if create-gh-release.sh fails
    else
        print_warning "No assets found to attach to GitHub release for v$FINAL_VERSION. Skipping GitHub release creation."
    fi
    echo # Newline
elif [ "$CREATE_GH_RELEASE" = true ] && [ -n "$DRY_RUN_FLAG" ]; then
    print_warning "DRY RUN: Would attempt to create GitHub release for v$FINAL_VERSION."
    echo # Newline
fi

# --- Cleanup Intermediate Files ---
if [ -z "$DRY_RUN_FLAG" ]; then
    if [ "$UPLOAD_ROCK_FILE_FLAG" = false ]; then # .rockspec was uploaded
        print_status "Cleaning up generated .rock files (since .rockspec was uploaded)..."
        for rock_file_to_clean in "${PACKED_ROCK_FILES[@]}"; do
            if [ -f "$rock_file_to_clean" ]; then
                rm -- "$rock_file_to_clean"
                print_status "Removed $rock_file_to_clean"
            else
                # This case should ideally not happen if build-rocks.sh reported success
                print_warning "Packed rock file $rock_file_to_clean (scheduled for cleanup) not found."
            fi
        done
        echo # Add a blank line for readability
    else     # .rock file was uploaded
        print_status "Generated .rock file(s) (${PACKED_ROCK_FILES[*]}) were specified for upload and are not automatically cleaned up."
        echo # Add a blank line for readability
    fi
fi

print_success "--------------------------------------------------"
print_success "RELEASE PROCESS COMPLETED SUCCESSFULLY for $PKG_NAME v$FINAL_VERSION!"
if [ -n "$PUBLISHED_LUAROCKS_URL" ]; then
    print_success "$PUBLISHED_LUAROCKS_URL"
fi
print_success "--------------------------------------------------"
if [ "$DRY_RUN_FLAG" = "--dry-run" ]; then print_warning "Remember, this was a DRY RUN."; fi
exit 0
