#!/usr/bin/env bash
#
# Script: read-pkg-name.sh
# Purpose: Reads the package name from the primary .spec.template file.
#          Outputs the extracted package name string to stdout.
#
# Usage: ./read-pkg-name.sh <spec_template_abs_path>
#   <spec_template_abs_path> : Absolute path to the primary spec template file
#                              (e.g., /path/to/project/releases/spec.template).
#
# Called by: releases/do-release.sh
# Assumptions:
#   - The spec template at <spec_template_abs_path> exists and contains a line like: package = "actual_package_name"
#
set -e

SPEC_TEMPLATE_PATH_ARG=$1

# Minimal colors for potential error messages if called directly
RED='\033[0;31m'
NC='\033[0m'

if [ -z "$SPEC_TEMPLATE_PATH_ARG" ]; then
    echo -e "${RED}[ERROR]${NC} Spec template path argument not provided." >&2
    exit 1
fi
if [ ! -f "$SPEC_TEMPLATE_PATH_ARG" ]; then
    echo -e "${RED}[ERROR]${NC} Spec template not found at [$SPEC_TEMPLATE_PATH_ARG]" >&2
    exit 1
fi

# Find the line with 'package =' and extract the value between quotes (single or double)
PKG_NAME_VALUE=$(grep -E 'package\s*=' "$SPEC_TEMPLATE_PATH_ARG" | awk -F"['\"]" '{print $2}')

if [ -z "$PKG_NAME_VALUE" ]; then
    echo -e "${RED}[ERROR]${NC} Could not find or parse package name from $SPEC_TEMPLATE_PATH_ARG" >&2
    echo -e "${RED}[INFO]${NC} Ensure the file contains a line like 'package = "your_pkg_name"' or 'package = \'your_pkg_name\''" >&2
    exit 1
fi

# Defensive check in case the placeholder was read (though spec.template should have actual name now).
if [ "$PKG_NAME_VALUE" = "@@PACKAGE_NAME@@" ]; then
    echo -e "${RED}[ERROR]${NC} Package name in $SPEC_TEMPLATE_PATH_ARG is still the placeholder '@@PACKAGE_NAME@@'. It should be a defined name." >&2
    exit 1
fi

echo "$PKG_NAME_VALUE"
