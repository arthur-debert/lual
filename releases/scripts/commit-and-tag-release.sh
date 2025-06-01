#!/usr/bin/env bash
#
# Script: commit-and-tag-release.sh
# Purpose: Commits specified release artifacts (spec.template, generated rockspec) to Git.
#          Creates a Git tag for the release version.
#          Pushes the commit and the tag to the remote repository (origin).
#
# Usage: ./commit-and-tag-release.sh [--dry-run] <spec_template_commit_path> <generated_rockspec_file1>
#   [--dry-run]                   : Optional. If present, simulates actions without actual Git operations.
#   <spec_template_commit_path> : Path to the spec.template file (relative to project root, e.g., releases/spec.template).
#   <generated_rockspec_file1>  : Filename of the generated rockspec to be committed (expected in CWD).
#
# Environment Variables Expected (set by caller, e.g., do-release.sh):
#   - FINAL_VERSION       : The version string for the release (e.g., "0.9.0"). Used for commit message and tag name.
#   - CWD is PROJECT_ROOT_ABS : Assumes script is run from the project root.
#
# Called by: releases/do-release.sh
# Assumptions:
#   - Git repository is initialized in the project root.
#   - `git` command is available.
#   - Files to be committed are specified by arguments and exist relative to CWD (PROJECT_ROOT_ABS).
#
set -e

DRY_RUN_ARG=""
SPEC_TEMPLATE_COMMIT_PATH_ARG=""

# Parse arguments: dry-run is optional first, then spec_template path, then rockspec file
if [ "$1" = "--dry-run" ]; then
    DRY_RUN_ARG="--dry-run"
    shift # Consume --dry-run argument
fi

if [ -z "$1" ]; then
    echo "Error: Path to spec.template (for commit) is required as first argument (after optional --dry-run)." >&2
    exit 1
fi
SPEC_TEMPLATE_COMMIT_PATH_ARG=$1
shift # Consume spec_template_path argument

# Check for necessary environment variables
if [ -z "$FINAL_VERSION" ]; then
    echo "Error: FINAL_VERSION env var not set." >&2
    exit 1
fi

# Remaining arguments are generated rockspec filenames (relative to CWD)
declare -a specs_to_add=()
for spec_arg in "$@"; do # Should only be one generated rockspec now
    if [ -n "$spec_arg" ]; then
        specs_to_add+=("$spec_arg")
    fi
done

# Files to commit: spec.template and the generated rockspec(s)
FILES_TO_COMMIT=("$SPEC_TEMPLATE_COMMIT_PATH_ARG" "${specs_to_add[@]}")

# Colors
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'
print_status_stderr() { echo -e "${BLUE}[INFO]${NC} $1" >&2; }
print_warning_stderr() { echo -e "${YELLOW}[WARNING]${NC} $1" >&2; }

if [ "${#specs_to_add[@]}" -eq 0 ]; then # Should always be at least one generated rockspec
    echo "Error: No valid generated rockspec files were provided to commit." >&2
    exit 1
fi

if [ -n "$(git status --porcelain)" ]; then
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
    if git diff-index --quiet --cached HEAD --; then
        print_status_stderr "No changes staged. Assuming files already committed or no actual changes."
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
