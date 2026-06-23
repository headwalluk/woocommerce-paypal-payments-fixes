#!/usr/bin/env bash
#
# prepare-analysis.sh
#
# Downloads the latest WooCommerce PayPal Payments release, extracts it, detects
# the version, creates a patched copy, and applies the best-match patch.
#
# Usage:
#   ./scripts/prepare-analysis.sh
#
# Output:
#   work/woocommerce-paypal-payments-X.Y.Z/          Clean plugin source
#   work/woocommerce-paypal-payments-X.Y.Z-patched/  Patched copy (best-match patch applied)

set -euo pipefail

SLUG="woocommerce-paypal-payments"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK_DIR="$REPO_ROOT/work"
PATCHES_DIR="$REPO_ROOT/patches"

# --- Download ---

mkdir -p "$WORK_DIR"

ZIP_URL="https://downloads.wordpress.org/plugin/${SLUG}.latest-stable.zip"
ZIP_FILE="$WORK_DIR/${SLUG}.zip"

echo "Downloading latest ${SLUG}..."
curl -sSL -o "$ZIP_FILE" "$ZIP_URL"
echo "Downloaded to $ZIP_FILE"

# --- Extract ---

# Remove any previous extraction
rm -rf "$WORK_DIR/$SLUG"

echo "Extracting..."
unzip -qo "$ZIP_FILE" -d "$WORK_DIR"

if [ ! -d "$WORK_DIR/$SLUG" ]; then
    echo "ERROR: Expected $SLUG/ directory not found after extraction."
    exit 1
fi

# --- Detect version ---

MAIN_PHP="$WORK_DIR/$SLUG/${SLUG}.php"
if [ ! -f "$MAIN_PHP" ]; then
    echo "ERROR: ${SLUG}.php not found at $MAIN_PHP"
    exit 1
fi

VERSION=$(grep -oP '^\s*\*\s*Version:\s*\K[0-9]+\.[0-9]+\.[0-9]+' "$MAIN_PHP" | head -1)
if [ -z "$VERSION" ]; then
    echo "ERROR: Could not detect ${SLUG} version from $MAIN_PHP"
    exit 1
fi

echo "Detected ${SLUG} version: $VERSION"

# --- Rename to versioned directory ---

CLEAN_DIR="$WORK_DIR/${SLUG}-${VERSION}"
PATCHED_DIR="$WORK_DIR/${SLUG}-${VERSION}-patched"

# Remove previous versioned directories if they exist
rm -rf "$CLEAN_DIR" "$PATCHED_DIR"

mv "$WORK_DIR/$SLUG" "$CLEAN_DIR"
echo "Clean source: $CLEAN_DIR"

# --- Create patched copy ---

cp -a "$CLEAN_DIR" "$PATCHED_DIR"
echo "Patched copy: $PATCHED_DIR"

# --- Find best-match patch ---
#
# Strategy: look for an exact version match first, then fall back to the
# most recent patch by version number (sorted with version-sort).

EXACT_PATCH="$PATCHES_DIR/${SLUG}-${VERSION}.patch"

if [ -f "$EXACT_PATCH" ]; then
    PATCH_FILE="$EXACT_PATCH"
    echo "Found exact patch: $(basename "$PATCH_FILE")"
else
    # Find the most recent patch by version sort
    PATCH_FILE=$(ls "$PATCHES_DIR"/${SLUG}-*.patch 2>/dev/null \
        | sort -V \
        | tail -1)

    if [ -z "$PATCH_FILE" ]; then
        echo "WARNING: No patches found in $PATCHES_DIR"
        echo "Skipping patch application. The patched directory is an unpatched copy."
        echo ""
        echo "=== Summary ==="
        echo "  ${SLUG} version : $VERSION"
        echo "  Clean directory   : $CLEAN_DIR"
        echo "  Patched directory : $PATCHED_DIR"
        echo "  Patch applied     : NONE"
        exit 0
    fi

    echo "No exact patch for $VERSION. Best match: $(basename "$PATCH_FILE")"
fi

# --- Apply patch ---
#
# Patches have paths like ${SLUG}-X.Y.Z/... or ${SLUG}-X.Y.Z-patched/...
# We strip the first component (-p1) and apply from inside the patched dir.

PATCH_VERSION=$(basename "$PATCH_FILE" .patch | sed "s/${SLUG}-//")
echo ""
echo "Applying $(basename "$PATCH_FILE") to patched directory..."

set +e
PATCH_OUTPUT=$(cd "$PATCHED_DIR" && patch -p1 --forward < "$PATCH_FILE" 2>&1)
PATCH_EXIT=$?
set -e

echo "$PATCH_OUTPUT"

# Check for rejects
REJECT_COUNT=$(find "$PATCHED_DIR" -name '*.rej' 2>/dev/null | wc -l)

echo ""
echo "=== Summary ==="
echo "  ${SLUG} version : $VERSION"
echo "  Patch applied     : $(basename "$PATCH_FILE") (for version $PATCH_VERSION)"
echo "  Clean directory   : $CLEAN_DIR"
echo "  Patched directory : $PATCHED_DIR"

if [ "$PATCH_EXIT" -eq 0 ] && [ "$REJECT_COUNT" -eq 0 ]; then
    echo "  Patch status      : CLEAN APPLY"
elif [ "$REJECT_COUNT" -gt 0 ]; then
    echo "  Patch status      : PARTIAL - $REJECT_COUNT reject file(s)"
    echo ""
    echo "Reject files:"
    find "$PATCHED_DIR" -name '*.rej' -print
    echo ""
    echo "Review the .rej files to see which hunks failed and need manual resolution."
else
    echo "  Patch status      : FAILED (exit code $PATCH_EXIT)"
fi

echo ""
echo "Next step: Run Claude Code and ask it to analyse the patched directory for new patch targets."
