#!/usr/bin/env bash
#
# Script: commit-and-tag-release.sh
# Purpose: Commits specified release artifacts (VERSION file, generated rockspecs) to Git.
#          Creates a Git tag for the release version.
#          Pushes the commit and the tag to the remote repository (origin).
#
# Usage: ./commit-and-tag-release.sh [--dry-run] <rockspec_file1> [rockspec_file2 ...]
#   [--dry-run]         : Optional. If present, simulates actions without actual Git operations.
#   <rockspec_fileN>    : Filename(s) of generated rockspec(s) to be committed (expected in CWD).
#
# Environment Variables Expected (set by caller, e.g., do-release.sh):
#   - FINAL_VERSION       : The version string for the release (e.g., "0.9.0"). Used for commit message and tag name.
#   - VERSION_FILE_ABS    : Absolute path to the VERSION file. Used to derive its basename for `git add`.
#   - CWD is PROJECT_ROOT_ABS : Assumes script is run from the project root.
#
# Called by: releases/do-release.sh
# Assumptions:
#   - Git repository is initialized in the project root.
#   - `git` command is available.
#   - Files to be committed (VERSION, rockspecs) are in the CWD (PROJECT_ROOT_ABS).
#
set -e

DRY_RUN_ARG=""
if [ "$1" = "--dry-run" ]; then
    DRY_RUN_ARG="--dry-run"
    shift # Consume --dry-run argument
fi

# Check for necessary environment variables
if [ -z "$FINAL_VERSION" ]; then
    echo "Error: FINAL_VERSION env var not set." >&2
    exit 1
fi
if [ -z "$VERSION_FILE_ABS" ]; then
    echo "Error: VERSION_FILE_ABS env var not set." >&2
    exit 1
fi

# Remaining arguments are rockspec filenames (relative to CWD)
declare -a specs_to_add=()
for spec_arg in "$@"; do
    if [ -n "$spec_arg" ]; then
        specs_to_add+=("$spec_arg")
    fi
done

# Files to commit are VERSION file (basename) and the provided rockspec filenames.
# Assumes CWD is PROJECT_ROOT_ABS, so basenames/relative paths are correct for git add.
FILES_TO_COMMIT=("$(basename "$VERSION_FILE_ABS")" "${specs_to_add[@]}")

# Colors (optional, for stderr messages if any)
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'
print_status_stderr() { echo -e "${BLUE}[INFO]${NC} $1" >&2; }
print_warning_stderr() { echo -e "${YELLOW}[WARNING]${NC} $1" >&2; }

if [ "${#specs_to_add[@]}" -eq 0 ]; then
    echo "Error: No valid rockspec files were provided to commit." >&2
    exit 1
fi

if [ -n "$(git status --porcelain)" ]; then
    # This warning occurs if there are any uncommitted changes *before* adding release files.
    print_warning_stderr "Git working directory is not perfectly clean. Staging specified files..."
fi

print_status_stderr "Adding files to git staging area:"
for f in "${FILES_TO_COMMIT[@]}"; do
    if [ -z "$f" ]; then
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
    # Check if there are any staged changes. If VERSION file and rockspecs haven't changed
    # (e.g. re-running for a version already prepared), this might be empty.
    if git diff-index --quiet --cached HEAD --; then
        print_status_stderr "No changes staged for commit. Assuming files already committed or no actual changes."
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
