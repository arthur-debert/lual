#!/usr/bin/env bash
#
# Script: manage-version.sh
# Purpose: Based on a current semantic version and user/flag input,
#          determines the next semantic version (e.g., after a bump).
#          Outputs the final chosen semantic version string (e.g., "1.2.3") to stdout.
#          This script performs NO FILE I/O itself; it only calculates versions.
#
# Usage: ./manage-version.sh <current_semantic_version> <scripts_dir_abs_path> [version_action_flag] [bump_type_if_any]
#   <current_semantic_version> : The current semantic version (e.g., "1.2.3") from the source spec file.
#   <scripts_dir_abs_path>     : Absolute path to the directory containing bump-version script.
#   [version_action_flag]      : Optional. Can be:
#                                  --use-current : Output current_semantic_version without change/prompt.
#                                  --bump-type   : Bump version by type specified in next arg, no prompt.
#   [bump_type_if_any]         : Required if version_action_flag is --bump-type.
#                                  Value must be "patch", "minor", or "major".
#
# Called by: releases/do-release.sh
# Calls:     <scripts_dir_abs_path>/bump-version
#
set -e

CURRENT_SEMANTIC_VERSION_ARG=$1
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

if [ -z "$CURRENT_SEMANTIC_VERSION_ARG" ]; then print_error "Current semantic version argument not provided."; fi
if ! echo "$CURRENT_SEMANTIC_VERSION_ARG" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    print_error "Provided current semantic version '$CURRENT_SEMANTIC_VERSION_ARG' must be X.Y.Z format."
fi
if [ -z "$SCRIPTS_DIR_ARG" ]; then print_error "Scripts directory path argument not provided."; fi

NEW_SEMANTIC_VERSION="$CURRENT_SEMANTIC_VERSION_ARG"

if [ "$VERSION_ACTION" = "--use-current" ]; then
    print_status "Using current version: $CURRENT_SEMANTIC_VERSION_ARG (as per --use-version-file/current flag)"
    # NEW_SEMANTIC_VERSION is already set to CURRENT_SEMANTIC_VERSION_ARG
elif [ "$VERSION_ACTION" = "--bump-type" ]; then
    if [[ ! "$BUMP_TYPE_ARG" =~ ^(patch|minor|major)$ ]]; then print_error "Invalid bump type '$BUMP_TYPE_ARG'."; fi
    print_status "Bumping version by '$BUMP_TYPE_ARG' (as per --bump flag)..."
    NEW_SEMANTIC_VERSION=$("$SCRIPTS_DIR_ARG/bump-version" "$BUMP_TYPE_ARG" "$CURRENT_SEMANTIC_VERSION_ARG")
    print_status "$BUMP_TYPE_ARG version bump: $CURRENT_SEMANTIC_VERSION_ARG → $NEW_SEMANTIC_VERSION"
else
    print_status "Current semantic version: $CURRENT_SEMANTIC_VERSION_ARG"
    echo >&2
    print_status "Choose action:"
    echo "1. Use current version ($CURRENT_SEMANTIC_VERSION_ARG)" >&2
    echo "2. Bump version" >&2
    echo >&2
    while true; do
        read -p "Select action (1-2): " -n 1 -r choice >&2
        echo >&2
        case $choice in
        1)
            print_status "Using current version: $CURRENT_SEMANTIC_VERSION_ARG"
            NEW_SEMANTIC_VERSION="$CURRENT_SEMANTIC_VERSION_ARG"
            break
            ;;
        2)
            echo >&2
            print_status "Select bump type:"
            PATCH_BUMP=$("$SCRIPTS_DIR_ARG/bump-version" patch "$CURRENT_SEMANTIC_VERSION_ARG")
            MINOR_BUMP=$("$SCRIPTS_DIR_ARG/bump-version" minor "$CURRENT_SEMANTIC_VERSION_ARG")
            MAJOR_BUMP=$("$SCRIPTS_DIR_ARG/bump-version" major "$CURRENT_SEMANTIC_VERSION_ARG")
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
            print_status "$BUMP_TYPE version bump: $CURRENT_SEMANTIC_VERSION_ARG → $NEW_SEMANTIC_VERSION"
            break
            ;;
        *) print_error "Invalid choice. Please select 1 or 2." ;;
        esac
    done
fi

echo "$NEW_SEMANTIC_VERSION" # Output the chosen/calculated semantic version
