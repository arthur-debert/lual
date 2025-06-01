#!/usr/bin/env bash
set -e

# Generates rockspec files from templates for the given version.
# Usage: ./gen-rockspecs.sh <version> [--with-extras]
# Outputs paths to generated rockspec files, one per line.

NEW_VERSION=$1
WITH_EXTRAS_ARG=$2 # Will be "--with-extras" or empty

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
PROJECT_ROOT="$SCRIPT_DIR/.."
cd "$PROJECT_ROOT" # Ensure we are in the project root

# --- Configuration ---
# IMPORTANT: Replace with your actual GitHub user/repo
REPO_URL="git+https://github.com/arthur-debert/lual.git"
GIT_TAG="v${NEW_VERSION}"
ROCK_REVISION="1" # Standard rockspec revision

LUAL_TEMPLATE="releases/lual.spec.template"
LUAL_ROCKSPEC="lual-${NEW_VERSION}-${ROCK_REVISION}.rockspec"

LUALEXTRAS_TEMPLATE="releases/lualextras.spec.template"
LUALEXTRAS_ROCKSPEC="lualextras-${NEW_VERSION}-${ROCK_REVISION}.rockspec"

# Colors (optional, for stderr messages if any)
BLUE='\033[0;34m'
NC='\033[0m'
print_status_stderr() { echo -e "${BLUE}[INFO]${NC} $1" >&2; }

if [ -z "$NEW_VERSION" ]; then
    echo "Error: Version argument is required." >&2
    exit 1
fi

# ---- Generate lual rockspec ----
print_status_stderr "Generating ${LUAL_ROCKSPEC} from ${LUAL_TEMPLATE}..."
if [ ! -f "$LUAL_TEMPLATE" ]; then
    echo "Error: Lual template not found: $LUAL_TEMPLATE" >&2
    exit 1
fi

cp "$LUAL_TEMPLATE" "$LUAL_ROCKSPEC"
# Replace placeholders. Add more sed commands if you have more placeholders.
# Ensure your templates use these exact placeholder strings.
sed -i.bak "s/{{VERSION}}/${NEW_VERSION}/g" "$LUAL_ROCKSPEC"
sed -i.bak "s/{{ROCK_REVISION}}/${ROCK_REVISION}/g" "$LUAL_ROCKSPEC"
sed -i.bak "s|{{REPO_URL}}|${REPO_URL}|g" "$LUAL_ROCKSPEC" # Use | as delimiter for URLs
sed -i.bak "s/{{GIT_TAG}}/${GIT_TAG}/g" "$LUAL_ROCKSPEC"
rm -f "${LUAL_ROCKSPEC}.bak"

print_status_stderr "Validating ${LUAL_ROCKSPEC}..."
if ! luarocks lint "$LUAL_ROCKSPEC"; then
    echo "Error: Validation failed for ${LUAL_ROCKSPEC}" >&2
    # rm "$LUAL_ROCKSPEC" # Optional: remove invalid spec
    exit 1
fi
echo "$LUAL_ROCKSPEC" # Output path to stdout

# ---- Generate lualextras rockspec (if requested) ----
if [ "$WITH_EXTRAS_ARG" = "--with-extras" ]; then
    print_status_stderr "Generating ${LUALEXTRAS_ROCKSPEC} from ${LUALEXTRAS_TEMPLATE}..."
    if [ ! -f "$LUALEXTRAS_TEMPLATE" ]; then
        echo "Error: Lualextras template not found: $LUALEXTRAS_TEMPLATE" >&2
        exit 1
    fi

    cp "$LUALEXTRAS_TEMPLATE" "$LUALEXTRAS_ROCKSPEC"
    sed -i.bak "s/{{VERSION}}/${NEW_VERSION}/g" "$LUALEXTRAS_ROCKSPEC"
    sed -i.bak "s/{{ROCK_REVISION}}/${ROCK_REVISION}/g" "$LUALEXTRAS_ROCKSPEC"
    sed -i.bak "s|{{REPO_URL}}|${REPO_URL}|g" "$LUALEXTRAS_ROCKSPEC"
    sed -i.bak "s/{{GIT_TAG}}/${GIT_TAG}/g" "$LUALEXTRAS_ROCKSPEC"
    rm -f "${LUALEXTRAS_ROCKSPEC}.bak"

    print_status_stderr "Validating ${LUALEXTRAS_ROCKSPEC}..."
    if ! luarocks lint "$LUALEXTRAS_ROCKSPEC"; then
        echo "Error: Validation failed for ${LUALEXTRAS_ROCKSPEC}" >&2
        # rm "$LUALEXTRAS_ROCKSPEC" # Optional: remove invalid spec
        exit 1
    fi
    echo "$LUALEXTRAS_ROCKSPEC" # Output path to stdout
fi
