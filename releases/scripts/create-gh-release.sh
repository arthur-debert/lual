#!/usr/bin/env bash
#
# Script: create-gh-release.sh
# Purpose: Creates a GitHub release using the 'gh' CLI, uploads specified assets,
#          and uses auto-generated release notes.
#
# Usage: ./create-gh-release.sh <tag_name> <asset_file_1> [asset_file_2 ...]
#   <tag_name>         : The Git tag for which to create the release (e.g., "v1.0.0").
#   <asset_file_N>     : Path(s) to asset file(s) to upload with the release.
#
# Environment Variables Expected:
#   - CWD is PROJECT_ROOT_ABS : Assumes script is run from the project root, which is a Git repository.
#   - GH_TOKEN (optional)     : GitHub token, if needed and not configured in gh CLI.
#
# Called by: releases/do-release.sh
# Assumptions:
#   - 'gh' CLI is installed and authenticated.
#   - The script is run from within the root of a Git repository.
#   - The tag already exists locally and ideally pushed to remote (do-release.sh handles this).

set -e

TAG_NAME_ARG=$1
shift # Consume tag name argument
# Remaining arguments are asset files
ASSET_FILES_ARGS=("$@")

# Colors & print functions for stderr
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'
print_status_stderr() { echo -e "${BLUE}[INFO]${NC} $1" >&2; }
print_success_stderr() { echo -e "${GREEN}[SUCCESS]${NC} $1" >&2; }
print_error_stderr() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
    exit 1
}

if [ -z "$TAG_NAME_ARG" ]; then
    print_error_stderr "Tag name argument not provided."
fi

if [ "${#ASSET_FILES_ARGS[@]}" -eq 0 ]; then
    print_error_stderr "No asset files provided for GitHub release '$TAG_NAME_ARG'."
fi

print_status_stderr "Preparing to create GitHub release for tag '$TAG_NAME_ARG'..."
print_status_stderr "Assets to upload: ${ASSET_FILES_ARGS[*]}"

# Construct the gh release create command
# We use --generate-notes for simplicity.
# Title will be same as tag by default if not specified with --title.
GH_COMMAND=("gh" "release" "create" "$TAG_NAME_ARG" "--generate-notes")

for asset_file in "${ASSET_FILES_ARGS[@]}"; do
    if [ ! -f "$asset_file" ]; then
        print_error_stderr "Asset file not found: $asset_file"
    fi
    GH_COMMAND+=("$asset_file") # Add asset file to the command
done

print_status_stderr "Executing: ${GH_COMMAND[*]}"

# Execute the command. Capture its combined output (stdout & stderr).
GH_EXEC_OUTPUT=$("${GH_COMMAND[@]}" 2>&1)
GH_EXIT_CODE=$? # Capture exit code immediately after execution

if [ $GH_EXIT_CODE -eq 0 ]; then
    print_success_stderr "Successfully created GitHub release for tag '$TAG_NAME_ARG' with assets."
    # Try to extract and print the release URL (gh usually prints it to stdout)
    RELEASE_URL=$(echo "$GH_EXEC_OUTPUT" | grep -Eo 'https://github.com/.*/releases/tag/[^[:space:]]+' | head -n 1)
    if [ -n "$RELEASE_URL" ]; then
        print_status_stderr "GitHub Release URL: $RELEASE_URL"
    else
        # If specific URL not found, print a portion of gh output if it seems like a success message / URL
        # This is a fallback, as gh output format might vary.
        POTENTIAL_INFO=$(echo "$GH_EXEC_OUTPUT" | head -n 5) # Show first 5 lines
        if [ -n "$POTENTIAL_INFO" ]; then
            print_status_stderr "(gh output on success):"
            echo "$POTENTIAL_INFO" >&2 # Print to stderr
        fi
    fi
else
    print_error_stderr "GitHub release creation failed for tag '$TAG_NAME_ARG'. Exit code: $GH_EXIT_CODE"
    if [ -n "$GH_EXEC_OUTPUT" ]; then
        echo -e "${RED}--- gh CLI output (stdout & stderr) ---${NC}" >&2
        echo "$GH_EXEC_OUTPUT" >&2
        echo -e "${RED}---------------------------------------${NC}" >&2
    fi
    # The script will exit here due to set -e and the print_error_stderr call.
fi
