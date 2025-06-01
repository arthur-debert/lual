#!/usr/bin/env bash
#
# Script: manage-version.sh
# Purpose: Reads the current version from the primary .spec.template file,
#          then either uses it directly, or prompts the user to bump (patch, minor, major),
#          or bumps automatically based on arguments.
#          If bumped, writes the new version back into the .spec.template file.
#          Outputs the final chosen semantic version string (e.g., "1.2.3") to stdout.
#
# Usage: ./manage-version.sh <spec_template_abs_path> <scripts_dir_abs_path> [version_action_flag] [bump_type_if_any]
#   <spec_template_abs_path> : Absolute path to the primary spec template file (e.g., /path/to/project/releases/spec.template).
#   <scripts_dir_abs_path>   : Absolute path to the directory containing bump-version script.
#   [version_action_flag]    : Optional. Can be:
#                                --use-current : Use version in spec.template without prompting.
#                                --bump-type   : Bump version by type specified in next arg, no prompt.
#   [bump_type_if_any]     : Required if version_action_flag is --bump-type.
#                              Value must be "patch", "minor", or "major".
#
# Called by: releases/do-release.sh
# Calls:     <scripts_dir_abs_path>/bump-version
#
# Assumptions:
#   - The spec template at <spec_template_abs_path> exists and contains a line like: version = "X.Y.Z-R"
#   - The bump-version script exists and functions correctly.
#
set -e

SPEC_TEMPLATE_PATH_ARG=$1
SCRIPTS_DIR_ARG=$2
VERSION_ACTION=$3
BUMP_TYPE_ARG=$4

# Colors
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() { echo -e "${BLUE}[INFO]${NC} $1" >&2; }
print_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
    exit 1
}

if [ -z "$SPEC_TEMPLATE_PATH_ARG" ]; then print_error "Spec template path argument not provided."; fi
if [ ! -f "$SPEC_TEMPLATE_PATH_ARG" ]; then print_error "Spec template not found at [$SPEC_TEMPLATE_PATH_ARG] (PWD is [$(pwd)])"; fi
if [ -z "$SCRIPTS_DIR_ARG" ]; then print_error "Scripts directory path argument not provided."; fi

# Read current version line from spec.template
# Example line: version = "0.8.10-1"
VERSION_LINE=$(grep -E '^[[:space:]]*version[[:space:]]*=[[:space:]]*"[0-9]+\.[0-9]+\.[0-9]+-[0-9]+"' "$SPEC_TEMPLATE_PATH_ARG")
if [ -z "$VERSION_LINE" ]; then print_error "Could not find valid version line in $SPEC_TEMPLATE_PATH_ARG"; fi

# Extract the full version string like "0.8.10-1"
FULL_VERSION_STRING=$(echo "$VERSION_LINE" | sed -E 's/^[[:space:]]*version[[:space:]]*=[[:space:]]*"([0-9]+\.[0-9]+\.[0-9]+-[0-9]+)".*$/\1/')

# Extract semantic version (X.Y.Z) and rockspec revision (-R)
SEMANTIC_VERSION=$(echo "$FULL_VERSION_STRING" | sed -E 's/([0-9]+\.[0-9]+\.[0-9]+)(-[0-9]+)?/\1/')
ROCKSPEC_REVISION_PART=$(echo "$FULL_VERSION_STRING" | sed -E 's/[0-9]+\.[0-9]+\.[0-9]+(-[0-9]+)?/\1/') # Will be like -1 or empty

if [ -z "$SEMANTIC_VERSION" ]; then print_error "Could not parse semantic version from '$FULL_VERSION_STRING' in $SPEC_TEMPLATE_PATH_ARG"; fi
# Default rockspec revision if not found (e.g. version = "1.2.3" without -1)
if [ -z "$ROCKSPEC_REVISION_PART" ]; then ROCKSPEC_REVISION_PART="-1"; fi # Default to -1 if not present

CURRENT_SEMANTIC_VERSION="$SEMANTIC_VERSION"
NEW_SEMANTIC_VERSION="$CURRENT_SEMANTIC_VERSION"

if [ "$VERSION_ACTION" = "--use-current" ]; then
    print_status "Using current version from spec template: $CURRENT_SEMANTIC_VERSION (rockspec revision: $ROCKSPEC_REVISION_PART)"
elif [ "$VERSION_ACTION" = "--bump-type" ]; then
    if [[ ! "$BUMP_TYPE_ARG" =~ ^(patch|minor|major)$ ]]; then print_error "Invalid bump type '$BUMP_TYPE_ARG'."; fi
    print_status "Bumping version by '$BUMP_TYPE_ARG' (as per --bump flag)..."
    NEW_SEMANTIC_VERSION=$("$SCRIPTS_DIR_ARG/bump-version" "$BUMP_TYPE_ARG" "$CURRENT_SEMANTIC_VERSION")
    print_status "$BUMP_TYPE_ARG version bump: $CURRENT_SEMANTIC_VERSION → $NEW_SEMANTIC_VERSION"
else
    print_status "Current semantic version in template: $CURRENT_SEMANTIC_VERSION (full: $FULL_VERSION_STRING)"
    echo >&2
    print_status "Choose action:"
    echo "1. Use current version ($CURRENT_SEMANTIC_VERSION)" >&2
    echo "2. Bump version" >&2
    echo >&2
    while true; do
        read -p "Select action (1-2): " -n 1 -r choice >&2
        echo >&2
        case $choice in
        1)
            print_status "Using current version: $CURRENT_SEMANTIC_VERSION"
            break
            ;;
        2)
            echo >&2
            print_status "Select bump type:"
            PATCH_BUMP=$("$SCRIPTS_DIR_ARG/bump-version" patch "$CURRENT_SEMANTIC_VERSION")
            MINOR_BUMP=$("$SCRIPTS_DIR_ARG/bump-version" minor "$CURRENT_SEMANTIC_VERSION")
            MAJOR_BUMP=$("$SCRIPTS_DIR_ARG/bump-version" major "$CURRENT_SEMANTIC_VERSION")
            echo "1. Patch ($PATCH_BUMP)" >&2
            echo "2. Minor ($MINOR_BUMP)" >&2
            echo "3. Major ($MAJOR_BUMP)" >&2
            echo >&2
            while true; do
                read -p "Select bump type (1-3): " -n 1 -r bump_choice >&2
                echo >&2
                case $bump_choice in
                1)
                    BUMP_TYPE="patch"
                    NEW_SEMANTIC_VERSION="$PATCH_BUMP"
                    break
                    ;;
                2)
                    BUMP_TYPE="minor"
                    NEW_SEMANTIC_VERSION="$MINOR_BUMP"
                    break
                    ;;
                3)
                    BUMP_TYPE="major"
                    NEW_SEMANTIC_VERSION="$MAJOR_BUMP"
                    break
                    ;;
                *) print_error "Invalid choice. Please select 1, 2, or 3." ;;
                esac
            done
            print_status "$BUMP_TYPE version bump: $CURRENT_SEMANTIC_VERSION → $NEW_SEMANTIC_VERSION"
            break
            ;;
        *) print_error "Invalid choice. Please select 1 or 2." ;;
        esac
    done
fi

if [ "$NEW_SEMANTIC_VERSION" != "$CURRENT_SEMANTIC_VERSION" ]; then
    NEW_FULL_VERSION_STRING="${NEW_SEMANTIC_VERSION}${ROCKSPEC_REVISION_PART}"
    print_status "Updating version in spec template ($SPEC_TEMPLATE_PATH_ARG) from '$FULL_VERSION_STRING' to '$NEW_FULL_VERSION_STRING'"
    # sed command to replace the version string in file
    # Using | as delimiter for sed because paths might contain /
    sed -i.bak "s|version = \"${FULL_VERSION_STRING}\"|version = \"${NEW_FULL_VERSION_STRING}\"|g" "$SPEC_TEMPLATE_PATH_ARG"
    rm -f "${SPEC_TEMPLATE_PATH_ARG}.bak"
fi

echo "$NEW_SEMANTIC_VERSION" # Output the semantic part for FINAL_VERSION in do-release.sh
