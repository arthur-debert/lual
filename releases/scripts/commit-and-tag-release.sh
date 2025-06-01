#!/usr/bin/env bash
#
# Script: commit-and-tag-release.sh
# Purpose: Commits specified release artifact files to Git.
#          Creates a Git tag for the release version.
#          Pushes the commit and the tag to the remote repository (origin).
#
# Usage: ./commit-and-tag-release.sh [--dry-run] <file_to_commit_1> [file_to_commit_2 ...]
#   [--dry-run]            : Optional. If present, simulates actions without actual Git operations.
#   <file_to_commit_N>     : Path(s) to file(s) to be committed (e.g., spec.template, generated rockspec).
#                            Paths are expected to be relative to project root (CWD).
#
# Environment Variables Expected (set by caller, e.g., do-release.sh):
#   - FINAL_VERSION          : The version string for the release (e.g., "0.9.0"). Used for commit message and tag name.
#   - CWD is PROJECT_ROOT_ABS: Assumes script is run from the project root.
#
# Called by: releases/do-release.sh
# Assumptions:
#   - Git repository is initialized in the project root.
#   - `git` command is available.
#   - Files to be committed are specified by arguments and exist relative to CWD (PROJECT_ROOT_ABS).
#
set -e

DRY_RUN_ARG=""
# Parse arguments: dry-run is optional first, then list of files.
if [ "$1" = "--dry-run" ]; then
    DRY_RUN_ARG="--dry-run"
    shift # Consume --dry-run argument
fi

# Check for necessary environment variables
if [ -z "$FINAL_VERSION" ]; then
    echo "Error: FINAL_VERSION env var not set." >&2
    exit 1
fi

# Remaining arguments are files to commit.
declare -a FILES_TO_COMMIT_ARGS=()
for arg_file in "$@"; do
    if [ -n "$arg_file" ]; then # Ensure argument is not an empty string
        FILES_TO_COMMIT_ARGS+=("$arg_file")
    fi
done

if [ "${#FILES_TO_COMMIT_ARGS[@]}" -eq 0 ]; then
    echo "Error: No files specified for commit." >&2
    exit 1
fi

# Colors
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'
print_status_stderr() { echo -e "${BLUE}[INFO]${NC} $1" >&2; }
print_warning_stderr() { echo -e "${YELLOW}[WARNING]${NC} $1" >&2; }

if [ -n "$(git status --porcelain)" ]; then
    # This warning means there were pre-existing uncommitted changes OR changes from previous steps
    # that this script is not directly responsible for adding (like spec.template modification).
    # The script will proceed to `git add` the files it *was* explicitly told to add.
    print_warning_stderr "Git working directory has changes. Staging specified files for this release commit..."
fi

print_status_stderr "Adding specified files to git staging area:"
for f in "${FILES_TO_COMMIT_ARGS[@]}"; do
    if [ -z "$f" ]; then # Should be caught by the loop that builds FILES_TO_COMMIT_ARGS
        print_warning_stderr "Skipping empty filename in commit list."
        continue
    fi
    print_status_stderr "  - $f"
    if [ "$DRY_RUN_ARG" != "--dry-run" ]; then git add "$f"; fi
done

COMMIT_MESSAGE="Release v${FINAL_VERSION}"
GIT_TAG="v${FINAL_VERSION}"
CURRENT_BRANCH=$(git branch --show-current)

if [ "$DRY_RUN_ARG" = "--dry-run" ]; then
    print_warning_stderr "DRY RUN: Would commit with message: '$COMMIT_MESSAGE'"
    print_warning_stderr "DRY RUN: Would create tag: '$GIT_TAG'"
    print_warning_stderr "DRY RUN: Would push branch '$CURRENT_BRANCH' and tag '$GIT_TAG'"
else
    if git diff-index --quiet --cached HEAD --; then
        print_status_stderr "No new changes staged for commit by this script. Commit may have already included these changes or files were unchanged."
    else
        print_status_stderr "Committing changes with message: '$COMMIT_MESSAGE'..."
        git commit -m "$COMMIT_MESSAGE"
    fi

    print_status_stderr "Checking if tag '$GIT_TAG' already exists..."
    if git rev-parse "$GIT_TAG" >/dev/null 2>&1; then
        print_warning_stderr "Tag '$GIT_TAG' already exists. Skipping tag creation."
    else
        print_status_stderr "Creating tag '$GIT_TAG'..."
        git tag "$GIT_TAG"
    fi

    print_status_stderr "Pushing branch '$CURRENT_BRANCH' to origin..."
    git push origin "$CURRENT_BRANCH"
    print_status_stderr "Pushing tag '$GIT_TAG' to origin..."
    git push origin "$GIT_TAG"
fi
